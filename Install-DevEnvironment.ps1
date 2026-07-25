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

function Update-SessionPath {
    $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = "$machinePath;$userPath"
}

function Test-WingetPackageInstalled {
    param([string]$Id)
    winget list --id $Id -e --accept-source-agreements *> $null
    return $LASTEXITCODE -eq 0
}

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Error "winget が見つかりません。Microsoft Store から「App Installer」をインストールしてください。"
    exit 1
}

$packagesPath = Join-Path $PSScriptRoot 'packages.json'
$packages = Get-Content $packagesPath -Raw | ConvertFrom-Json

foreach ($pkg in $packages) {
    if (Test-WingetPackageInstalled -Id $pkg.Id) {
        Write-Host "[Check] $($pkg.Name) は導入済みです。最新版か確認しています..."
        winget upgrade --id $pkg.Id -e --accept-package-agreements --accept-source-agreements --silent
        if ($LASTEXITCODE -eq 0) {
            Write-Host "[OK] $($pkg.Name) を最新版に更新しました"
            $results += [PSCustomObject]@{ Name = $pkg.Name; Status = 'Updated' }
        } elseif ($LASTEXITCODE -eq $script:WINGET_NO_APPLICABLE_UPDATE) {
            Write-Host "[Skip] $($pkg.Name) は既に最新版です"
            $results += [PSCustomObject]@{ Name = $pkg.Name; Status = 'Skip (最新版)' }
        } else {
            Write-Warning "[NG] $($pkg.Name) の更新確認に失敗しました (exit code: $LASTEXITCODE)"
            $results += [PSCustomObject]@{ Name = $pkg.Name; Status = "Failed to update (exit code: $LASTEXITCODE)" }
        }
        continue
    }

    Write-Host "[Install] $($pkg.Name) をインストールしています..."
    winget install --id $pkg.Id -e --accept-package-agreements --accept-source-agreements --silent
    if ($LASTEXITCODE -eq 0) {
        Write-Host "[OK] $($pkg.Name) のインストールが完了しました"
        $results += [PSCustomObject]@{ Name = $pkg.Name; Status = 'Installed' }
    } else {
        Write-Warning "[NG] $($pkg.Name) のインストールに失敗しました (exit code: $LASTEXITCODE)"
        $results += [PSCustomObject]@{ Name = $pkg.Name; Status = "Failed (exit code: $LASTEXITCODE)" }
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
    $beforeVersion = if ($alreadyInstalled) { (& claude --version) 2>$null } else { $null }

    if ($alreadyInstalled) {
        Write-Host "[Check] Claude Code CLI は導入済みです。最新版か確認しています..."
    } else {
        Write-Host "[Install] Claude Code CLI をインストールしています..."
    }

    npm install -g @anthropic-ai/claude-code
    if ($LASTEXITCODE -eq 0) {
        Update-SessionPath
        $afterVersion = (& claude --version) 2>$null
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
