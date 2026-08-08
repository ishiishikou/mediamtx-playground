[CmdletBinding()]
param(
    [string]$Distro,
    [switch]$SkipFirewall
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

if (-not $SkipFirewall -and -not (Test-IsAdministrator)) {
    Write-Host 'Windows Firewallの一時ルールを削除するため、管理者権限へ昇格します。'
    $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    if (-not [string]::IsNullOrWhiteSpace($Distro)) {
        $arguments += " -Distro `"$Distro`""
    }
    $process = Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $arguments -Wait -PassThru
    exit $process.ExitCode
}

$repositoryRoot = Get-SmartphoneRepositoryRoot
$context = Get-WslRepositoryContext -RepositoryRoot $repositoryRoot -Distro $Distro

Write-Host 'MediaMTXスマートフォン検証環境とローカル証明書を削除します。'
Invoke-WslRepositoryCommand -Context $context -Command 'docker compose -f examples/docker-compose.smartphone.yml down --remove-orphans' -IgnoreExitCode | Out-Null

if (-not $SkipFirewall) {
    Remove-SmartphoneFirewallRules
}

Invoke-WslRepositoryCommand -Context $context -Command 'rm -rf tmp/smartphone' | Out-Null

Write-Host 'PC側の検証用コンテナ、Firewallルール、CA/証明書を削除しました。' -ForegroundColor Green
Write-Host 'iPhoneにインストールしたCAプロファイルは、iPhoneの設定から手動で削除してください。' -ForegroundColor Yellow
