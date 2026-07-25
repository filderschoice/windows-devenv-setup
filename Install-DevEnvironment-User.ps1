<#
Windows開発環境ブートストラップスクリプト(ユーザー権限専用版)。
管理者権限なしで、packages.json に列挙された winget パッケージ(--scope user)と
Claude Code CLI (npm) を、未導入のものだけインストールする。再実行しても安全(冪等)。
#>

$ErrorActionPreference = 'Stop'
$results = @()

function Test-IsElevated {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

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

if (Test-IsElevated) {
    Write-Warning "このスクリプトはユーザー権限専用です。管理者権限で実行されていますが、そのまま処理を続行します(管理者権限が必要なパッケージがある場合は Install-DevEnvironment.ps1 を使用してください)。"
}

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Error "winget が見つかりません。Microsoft Store から「App Installer」をインストールしてください。"
    exit 1
}

$packagesPath = Join-Path $PSScriptRoot 'packages.json'
$packages = Get-Content $packagesPath -Raw | ConvertFrom-Json

foreach ($pkg in $packages) {
    if (Test-WingetPackageInstalled -Id $pkg.Id) {
        Write-Host "[Skip] $($pkg.Name) は既にインストール済みです"
        $results += [PSCustomObject]@{ Name = $pkg.Name; Status = 'Skip (既にインストール済み)' }
        continue
    }

    Write-Host "[Install] $($pkg.Name) をインストールしています(ユーザースコープ)..."
    winget install --id $pkg.Id -e --scope user --accept-package-agreements --accept-source-agreements --silent
    if ($LASTEXITCODE -eq 0) {
        Write-Host "[OK] $($pkg.Name) のインストールが完了しました"
        $results += [PSCustomObject]@{ Name = $pkg.Name; Status = 'Installed' }
    } else {
        Write-Warning "[NG] $($pkg.Name) のインストールに失敗しました (exit code: $LASTEXITCODE) - ユーザースコープ非対応で管理者権限が必要な可能性があります。その場合は Install-DevEnvironment.ps1 をご利用ください。"
        $results += [PSCustomObject]@{ Name = $pkg.Name; Status = "Failed (exit code: $LASTEXITCODE) - 管理者権限が必要な可能性あり" }
    }
}

Write-Host "`nPATH を更新しています..."
Update-SessionPath

if (Get-Command claude -ErrorAction SilentlyContinue) {
    Write-Host "[Skip] Claude Code CLI は既にインストール済みです"
    $results += [PSCustomObject]@{ Name = 'Claude Code CLI'; Status = 'Skip (既にインストール済み)' }
} elseif (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
    Write-Warning "[NG] npm が見つからないため Claude Code CLI をインストールできません(Node.jsの導入状況を確認してください)"
    $results += [PSCustomObject]@{ Name = 'Claude Code CLI'; Status = 'Failed (npm not found)' }
} else {
    Write-Host "[Install] Claude Code CLI をインストールしています..."
    npm install -g @anthropic-ai/claude-code
    if ($LASTEXITCODE -eq 0) {
        Write-Host "[OK] Claude Code CLI のインストールが完了しました"
        $results += [PSCustomObject]@{ Name = 'Claude Code CLI'; Status = 'Installed' }
    } else {
        Write-Warning "[NG] Claude Code CLI のインストールに失敗しました (exit code: $LASTEXITCODE)"
        $results += [PSCustomObject]@{ Name = 'Claude Code CLI'; Status = "Failed (exit code: $LASTEXITCODE)" }
    }
}

Write-Host "`n=== インストール結果サマリ ==="
$results | Format-Table -AutoSize
