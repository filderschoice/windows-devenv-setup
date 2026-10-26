<#
Windows開発環境ブートストラップスクリプト。
packages.json に列挙された winget パッケージと Claude Code CLI (npm) を、
未導入のものはインストールし、導入済みのものは最新版かどうかを確認して
必要であれば更新する。再実行しても安全(冪等)。
#>

$ErrorActionPreference = 'Stop'
$results = @()

# winget upgrade が「利用可能なアップグレードなし」を表す際の終了コード (0x8A15002B)。
$script:WINGET_NO_APPLICABLE_UPDATE = -1978335189

function Test-IsElevated {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Update-SessionPath {
    # Machine + User の PATH を現在のセッションへ反映する。単純に上書きすると、
    # このセッションにだけ追加されていたエントリ(例: nvm use や開発用シェルが足したパス)が
    # 消えてしまうため、既存の $env:Path も残したうえで空要素と重複を取り除く。
    $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')

    $merged = [System.Collections.Generic.List[string]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in (@($machinePath, $userPath, $env:Path) -join ';') -split ';') {
        $trimmed = $entry.Trim()
        if (-not $trimmed) { continue }
        if ($seen.Add($trimmed.TrimEnd('\'))) {
            $merged.Add($trimmed)
        }
    }
    $env:Path = $merged -join ';'
}

function Get-RawUserPath {
    # ユーザーPATHを HKCU:\Environment から「展開せずに」読む。
    # [Environment]::GetEnvironmentVariable('Path', 'User') は %NVM_HOME% のような
    # 環境変数参照を展開した値を返すため、それをそのまま書き戻すと参照が実パスで焼き付き、
    # 後から NVM 等が変数を切り替えても PATH が追随しなくなる。
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment')
    if (-not $key) {
        return @{ Value = ''; Kind = [Microsoft.Win32.RegistryValueKind]::ExpandString }
    }
    try {
        $value = $key.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        $kind = try { $key.GetValueKind('Path') } catch { [Microsoft.Win32.RegistryValueKind]::ExpandString }
        return @{ Value = [string]$value; Kind = $kind }
    } finally {
        $key.Dispose()
    }
}

function Publish-EnvironmentChange {
    # レジストリを直接書いた場合は [Environment]::SetEnvironmentVariable と違って
    # WM_SETTINGCHANGE が飛ばず、Explorer や以降に起動するプロセスへ変更が伝わらない。
    # 通知に失敗してもインストール自体は続行させる(再ログオンで反映されるため)。
    try {
        if (-not ('Win32.NativeMethods' -as [type])) {
            Add-Type -Namespace 'Win32' -Name 'NativeMethods' -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("user32.dll", SetLastError = true, CharSet = System.Runtime.InteropServices.CharSet.Auto)]
public static extern System.IntPtr SendMessageTimeout(System.IntPtr hWnd, uint Msg, System.IntPtr wParam, string lParam, uint fuFlags, uint uTimeout, out System.UIntPtr lpdwResult);
'@
        }
        $result = [UIntPtr]::Zero
        # HWND_BROADCAST = 0xffff, WM_SETTINGCHANGE = 0x1A, SMTO_ABORTIFHUNG = 0x0002
        [void][Win32.NativeMethods]::SendMessageTimeout([IntPtr]0xffff, 0x1A, [IntPtr]::Zero, 'Environment', 0x0002, 5000, [ref]$result)
    } catch {
        Write-Warning "環境変数の変更通知(WM_SETTINGCHANGE)に失敗しました。新しいプロセスへの反映は再ログオン後になります: $($_.Exception.Message)"
    }
}

function Test-WingetPackageInstalled {
    param([string]$Id)
    winget list --id $Id -e --accept-source-agreements *> $null
    return $LASTEXITCODE -eq 0
}

function Get-BlockingProcess {
    # インストーラ(Inno Setup 等)が「使用中のプロセスがある」として中断した場合、そのプロセス名と PID が
    # winget のインストーラログに残る(例: Git for Windows の keyboxd.exe)。直前の実行で書かれた
    # ログだけを対象に、まだ生きているプロセスを返す。PID は再利用されうるので名前も照合する。
    param([string]$PackageId, [datetime]$Since)
    $logDir = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\LocalState\DiagOutputDir'
    $log = Get-ChildItem -Path $logDir -Filter "$PackageId.*.log" -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -ge $Since } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if (-not $log) { return @() }

    $found = @()
    $text = Get-Content -LiteralPath $log.FullName -Raw -ErrorAction SilentlyContinue
    foreach ($m in [regex]::Matches($text, '(?m)^\s*(\S+)\.exe \(PID (\d+)\)')) {
        $proc = Get-Process -Id ([int]$m.Groups[2].Value) -ErrorAction SilentlyContinue
        if ($proc -and $proc.ProcessName -eq $m.Groups[1].Value) {
            $found += $proc
        }
    }
    return $found
}

function Invoke-WingetWithRetry {
    # winget を実行して終了コードを返す。インストーラが「使用中のプロセス」で失敗した場合に限り、
    # 対象プロセスを示してユーザーに確認し、同意があれば停止して1回だけ再実行する。
    # 同意がない・対話できない場合は何も止めず、元の終了コードをそのまま返す。
    param([string[]]$WingetArgs, [string]$PackageId, [string]$PackageName)
    $startedAt = Get-Date
    winget @WingetArgs | Out-Host
    $code = $LASTEXITCODE
    if ($code -eq 0 -or $code -eq $script:WINGET_NO_APPLICABLE_UPDATE) { return $code }

    $blockers = @(Get-BlockingProcess -PackageId $PackageId -Since $startedAt)
    if ($blockers.Count -eq 0) { return $code }

    Write-Warning "$PackageName のインストーラが、使用中の次のプロセスを理由に中断しました:"
    foreach ($p in $blockers) { Write-Host "    $($p.ProcessName).exe (PID $($p.Id))" }
    try {
        $answer = Read-Host "これらを停止して再試行しますか? (停止中の処理は失われます) [y/N]"
    } catch {
        $answer = ''
    }
    if ($answer -notmatch '^[yY]') {
        Write-Host "[Skip] プロセスは停止せず、再試行しません"
        return $code
    }

    foreach ($p in $blockers) {
        try {
            Stop-Process -Id $p.Id -Force -ErrorAction Stop
        } catch {
            Write-Warning "$($p.ProcessName).exe (PID $($p.Id)) を停止できませんでした: $($_.Exception.Message)"
        }
    }
    Start-Sleep -Seconds 1
    Write-Host "[Retry] $PackageName を再試行しています..."
    winget @WingetArgs | Out-Host
    return $LASTEXITCODE
}

function Resolve-AppPath {
    # winget/MSIインストーラがPATHを更新しない場合でも、App Pathsレジストリに
    # 実行ファイルの場所が登録されていることが多い(例: PowerShell 7の pwsh.exe)。
    param([string]$ExeName)
    foreach ($hive in 'HKLM:', 'HKCU:') {
        $key = Join-Path $hive "SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\$ExeName"
        $prop = Get-ItemProperty -Path $key -ErrorAction SilentlyContinue
        if (-not $prop) { continue }
        # 既定値は引用符付きで登録されていることがある(例: "C:\Program Files\...\app.exe")。
        # そのまま Split-Path に渡すとパスの先頭に " が残るため、前後の空白と引用符を落とす。
        $target = ([string]$prop.'(default)').Trim().Trim('"')
        if ($target) {
            return Split-Path $target -Parent
        }
    }
    return $null
}

function Add-UserPathEntry {
    param([string]$Directory)
    $raw = Get-RawUserPath
    $entries = @($raw.Value -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $normalized = $Directory.TrimEnd('\')
    if ($entries | Where-Object { $_.TrimEnd('\') -eq $normalized }) {
        return $false
    }

    $newPath = if ($raw.Value) { "$($raw.Value.TrimEnd(';'));$Directory" } else { $Directory }
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true)
    try {
        $key.SetValue('Path', $newPath, $raw.Kind)
    } finally {
        $key.Dispose()
    }
    Publish-EnvironmentChange
    return $true
}

function Sync-PackagePath {
    # packages.json で ExeName が指定されているパッケージについて、コマンドが解決できるか確認し、
    # できない場合は App Paths レジストリから実体を探してユーザーPATHへ追加する。
    param($Package)
    Update-SessionPath
    if (Get-Command $Package.ExeName -ErrorAction SilentlyContinue) {
        return @()
    }

    $dir = Resolve-AppPath -ExeName $Package.ExeName
    if (-not $dir -or -not (Test-Path $dir)) {
        Write-Warning "[NG] $($Package.Name) の実行ファイル ($($Package.ExeName)) が見つからず、PATHへの追加をスキップしました"
        return @([PSCustomObject]@{ Name = "$($Package.Name) (PATH)"; Status = "Failed to locate $($Package.ExeName)" })
    }

    if (Add-UserPathEntry -Directory $dir) {
        Update-SessionPath
        Write-Host "[OK] $($Package.Name) のパスをユーザーPATHに追加しました ($dir)"
        return @([PSCustomObject]@{ Name = "$($Package.Name) (PATH)"; Status = "Added to PATH ($dir)" })
    }

    return @()
}

function Get-ClaudeVersion {
    # claude --version は複数行を返すことがあり、その場合 (& claude --version) は配列になる。
    # 配列のまま -eq で比較すると「一致する要素の抽出」になり更新判定が壊れるため、
    # 必ず単一の文字列へ畳み込んで返す。未導入・実行失敗時は $null。
    if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
        return $null
    }
    try {
        $output = & claude --version 2>$null
        if ($LASTEXITCODE -ne 0) {
            return $null
        }
        return (($output -join ' ').Trim())
    } catch {
        return $null
    }
}

if (-not (Test-IsElevated)) {
    Write-Warning "管理者権限で実行されていません。マシンスコープでのインストールが必要なパッケージは失敗する可能性があります(その場合は管理者として実行し直すか、Install-DevEnvironment-User.ps1 をご利用ください)。"
}

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    # $ErrorActionPreference = 'Stop' のため、Write-Error をそのまま使うと終端エラーとして
    # 中断してしまい exit 1 に到達しない。-ErrorAction Continue で明示的に終了コードを返す。
    Write-Error "winget が見つかりません。Microsoft Store から「App Installer」をインストールしてください。" -ErrorAction Continue
    exit 1
}

# ドットソース実行など $PSScriptRoot が空になる経路でも動くようにフォールバックする。
$scriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$packagesPath = Join-Path $scriptRoot 'packages.json'
if (-not (Test-Path $packagesPath)) {
    Write-Error "packages.json が見つかりません ($packagesPath)。スクリプトと同じフォルダに配置してください。" -ErrorAction Continue
    exit 1
}
# -Encoding UTF8 は必須。Windows PowerShell 5.1 は既定でANSIとして読むため、
# packages.json の Name に日本語を書くと指定なしでは文字化けする(BOM付きJSONにも耐える)。
$packages = Get-Content $packagesPath -Raw -Encoding UTF8 | ConvertFrom-Json

foreach ($pkg in $packages) {
    # インストール/更新が成功したときだけ、後段のPATH確認を行うためのフラグ。
    $stepSucceeded = $false

    if (Test-WingetPackageInstalled -Id $pkg.Id) {
        Write-Host "[Check] $($pkg.Name) は導入済みです。最新版か確認しています..."
        $exitCode = Invoke-WingetWithRetry -PackageId $pkg.Id -PackageName $pkg.Name -WingetArgs @('upgrade', '--id', $pkg.Id, '-e', '--accept-package-agreements', '--accept-source-agreements', '--silent')
        if ($exitCode -eq 0) {
            Write-Host "[OK] $($pkg.Name) を最新版に更新しました"
            $results += [PSCustomObject]@{ Name = $pkg.Name; Status = 'Updated' }
            $stepSucceeded = $true
        } elseif ($exitCode -eq $script:WINGET_NO_APPLICABLE_UPDATE) {
            Write-Host "[Skip] $($pkg.Name) は既に最新版です"
            $results += [PSCustomObject]@{ Name = $pkg.Name; Status = 'Skip (最新版)' }
            $stepSucceeded = $true
        } else {
            Write-Warning "[NG] $($pkg.Name) の更新確認に失敗しました (exit code: $exitCode)"
            $results += [PSCustomObject]@{ Name = $pkg.Name; Status = "Failed to update (exit code: $exitCode)" }
        }
    } else {
        Write-Host "[Install] $($pkg.Name) をインストールしています..."
        $exitCode = Invoke-WingetWithRetry -PackageId $pkg.Id -PackageName $pkg.Name -WingetArgs @('install', '--id', $pkg.Id, '-e', '--accept-package-agreements', '--accept-source-agreements', '--silent')
        if ($exitCode -eq 0) {
            Write-Host "[OK] $($pkg.Name) のインストールが完了しました"
            $results += [PSCustomObject]@{ Name = $pkg.Name; Status = 'Installed' }
            $stepSucceeded = $true
        } else {
            Write-Warning "[NG] $($pkg.Name) のインストールに失敗しました (exit code: $exitCode)"
            $results += [PSCustomObject]@{ Name = $pkg.Name; Status = "Failed (exit code: $exitCode)" }
        }
    }

    if ($pkg.ExeName) {
        if ($stepSucceeded) {
            $results += Sync-PackagePath -Package $pkg
        } else {
            # 導入に失敗した状態でPATHを探しても「見つからない」警告が増えるだけなので行わない。
            Write-Host "[Skip] $($pkg.Name) のPATH確認は、インストール/更新に失敗したためスキップします"
        }
    }
}

Write-Host "`nPATH を更新しています..."
Update-SessionPath

if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
    if (Get-Command claude -ErrorAction SilentlyContinue) {
        Write-Host "[Skip] Claude Code CLI は既にインストール済みです(npm が見つからないため更新確認はスキップします)"
        $results += [PSCustomObject]@{ Name = 'Claude Code CLI'; Status = 'Skip (npm not found)' }
    } else {
        Write-Warning "[NG] npm が見つからないため Claude Code CLI をインストールできません(Node.jsの導入状況を確認してください)"
        $results += [PSCustomObject]@{ Name = 'Claude Code CLI'; Status = 'Failed (npm not found)' }
    }
} else {
    $alreadyInstalled = [bool](Get-Command claude -ErrorAction SilentlyContinue)
    $beforeVersion = Get-ClaudeVersion

    if ($alreadyInstalled) {
        Write-Host "[Check] Claude Code CLI は導入済みです。最新版か確認しています..."
    } else {
        Write-Host "[Install] Claude Code CLI をインストールしています..."
    }

    npm install -g @anthropic-ai/claude-code
    if ($LASTEXITCODE -eq 0) {
        Update-SessionPath
        $afterVersion = Get-ClaudeVersion
        if ($alreadyInstalled -and $beforeVersion -eq $afterVersion) {
            Write-Host "[Skip] Claude Code CLI は既に最新版です ($afterVersion)"
            $results += [PSCustomObject]@{ Name = 'Claude Code CLI'; Status = 'Skip (最新版)' }
        } elseif ($alreadyInstalled) {
            Write-Host "[OK] Claude Code CLI を最新版に更新しました ($beforeVersion -> $afterVersion)"
            $results += [PSCustomObject]@{ Name = 'Claude Code CLI'; Status = 'Updated' }
        } else {
            Write-Host "[OK] Claude Code CLI のインストールが完了しました"
            $results += [PSCustomObject]@{ Name = 'Claude Code CLI'; Status = 'Installed' }
        }
    } else {
        $action = if ($alreadyInstalled) { '更新' } else { 'インストール' }
        Write-Warning "[NG] Claude Code CLI の$($action)に失敗しました (exit code: $LASTEXITCODE)"
        $results += [PSCustomObject]@{ Name = 'Claude Code CLI'; Status = "Failed (exit code: $LASTEXITCODE)" }
    }
}

Write-Host "`n=== インストール結果サマリ ==="
$results | Format-Table -AutoSize

# 個々の失敗ではループを止めない代わりに、最後にまとめて終了コードへ反映する
# (呼び出し側や自動実行から成否を判定できるようにするため)。
$failed = @($results | Where-Object { $_.Status -like 'Failed*' })
if ($failed.Count -gt 0) {
    Write-Warning "$($failed.Count) 件が失敗しました。上記サマリの Status を確認してください。"
    exit 1
}
