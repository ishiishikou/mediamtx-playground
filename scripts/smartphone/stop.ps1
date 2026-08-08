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

Write-Host 'MediaMTXスマートフォン検証環境を停止します。'

try {
    $repositoryRoot = Get-SmartphoneRepositoryRoot
    $context = Get-WslRepositoryContext -RepositoryRoot $repositoryRoot -Distro $Distro
    Invoke-WslRepositoryCommand -Context $context -Command 'docker compose -f examples/docker-compose.smartphone.yml down --remove-orphans' -IgnoreExitCode | Out-Null
}
catch {
    Write-Warning "Docker Compose停止処理でエラーが発生しました: $($_.Exception.Message)"
}
finally {
    if (-not $SkipFirewall) {
        Remove-SmartphoneFirewallRules
        Write-Host 'Windows Firewallの一時ルールを削除しました。'
    }
}

Write-Host '停止処理が完了しました。証明書は tmp/smartphone/ に残っています。' -ForegroundColor Green
