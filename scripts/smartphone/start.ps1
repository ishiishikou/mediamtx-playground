[CmdletBinding()]
param(
    [string]$LanIp,
    [string]$Distro,
    [switch]$SkipFirewall
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

if (-not $SkipFirewall -and -not (Test-IsAdministrator)) {
    Write-Host 'Windows Firewallの一時ルールを設定するため、管理者権限へ昇格します。'
    $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    if (-not [string]::IsNullOrWhiteSpace($LanIp)) {
        $arguments += " -LanIp `"$LanIp`""
    }
    if (-not [string]::IsNullOrWhiteSpace($Distro)) {
        $arguments += " -Distro `"$Distro`""
    }

    $process = Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $arguments -Wait -PassThru
    exit $process.ExitCode
}

$repositoryRoot = Get-SmartphoneRepositoryRoot
$context = Get-WslRepositoryContext -RepositoryRoot $repositoryRoot -Distro $Distro

if ([string]::IsNullOrWhiteSpace($LanIp)) {
    $LanIp = Get-PreferredLanIPv4
}
Assert-IPv4Address -Address $LanIp

$composeFile = 'examples/docker-compose.smartphone.yml'
$composeStarted = $false
$firewallAdded = $false
$composeEnv = 'export SMARTPHONE_LAN_IP=' + $LanIp + '; export SMARTPHONE_UID=$(id -u); export SMARTPHONE_GID=$(id -g); '

try {
    Write-Host "[1/7] WSL/Dockerを確認します: $($context.RepoPath)"
    Invoke-WslRepositoryCommand -Context $context -Command 'docker version >/dev/null && docker compose version >/dev/null' | Out-Null

    Write-Host '[2/7] 前回のコンテナとFirewallルールを掃除します。'
    Invoke-WslRepositoryCommand -Context $context -Command "${composeEnv}docker compose -f $composeFile down --remove-orphans >/dev/null 2>&1 || true" -IgnoreExitCode | Out-Null
    if (-not $SkipFirewall) {
        Remove-SmartphoneFirewallRules
    }

    Write-Host '[3/7] mkcertコンテナを準備します。'
    Invoke-WslRepositoryCommand -Context $context -Command 'mkdir -p tmp/smartphone/certs/ca tmp/smartphone/public tmp/smartphone/generated' | Out-Null
    Invoke-WslRepositoryCommand -Context $context -Command "${composeEnv}docker compose -f $composeFile build cert-generator" | Out-Null

    Write-Host "[4/7] 検証用CAと ${LanIp} 向けサーバー証明書を生成します。"
    Invoke-WslRepositoryCommand -Context $context -Command "${composeEnv}docker compose -f $composeFile run --rm cert-generator" | Out-Null

    if (-not $SkipFirewall) {
        Write-Host '[5/7] Windows FirewallをLocalSubnet限定で一時開放します。'
        Add-SmartphoneFirewallRules
        $firewallAdded = $true
    }
    else {
        Write-Host '[5/7] -SkipFirewall が指定されたためFirewall設定を変更しません。'
    }

    Write-Host '[6/7] MediaMTXとCA配信サーバーを起動します。'
    Invoke-WslRepositoryCommand -Context $context -Command "${composeEnv}docker compose -f $composeFile up -d mediamtx cert-server" | Out-Null
    $composeStarted = $true

    Write-Host '[7/7] WindowsのLAN IP経由でTCP疎通を確認します。'
    Start-Sleep -Seconds 1
    $caReady = Test-NetConnection -ComputerName $LanIp -Port 8000 -InformationLevel Quiet -WarningAction SilentlyContinue
    $httpsReady = Test-NetConnection -ComputerName $LanIp -Port 8889 -InformationLevel Quiet -WarningAction SilentlyContinue
    if (-not $caReady -or -not $httpsReady) {
        throw @"
WindowsのLAN IP ($LanIp) からDocker公開ポートへ到達できませんでした。
Docker DesktopのWSL 2 integrationを利用している場合はDocker Desktopが起動しているか確認してください。
WSL内に独立してDocker Engineを入れている場合、既定のWSL NATではLANからWSLへ直接到達できないため、WSL mirrored networking等の追加設定が必要です。
Firewallとコンテナはfinallyで自動的に元へ戻します。
"@
    }

    Write-Host ''
    Write-Host 'スマートフォンWebRTC検証環境を起動しました。' -ForegroundColor Green
    Write-Host "LAN IP              : $LanIp"
    Write-Host "CA取得URL            : http://${LanIp}:8000/rootCA.pem"
    Write-Host "WebRTC publish URL   : https://${LanIp}:8889/live/iphone-001/publish"
    Write-Host "WebRTC viewer URL    : https://${LanIp}:8889/live/iphone-001"
    Write-Host 'publisher user       : poc-publisher'
    Write-Host 'publisher password   : poc-publisher-pass'
    Write-Host ''
    Write-Host 'iPhone初回のみ:'
    Write-Host '  1. CA取得URLをSafariで開いてrootCA.pemを取得'
    Write-Host '  2. 設定 > ダウンロード済みのプロファイル からCAをインストール'
    Write-Host '  3. 設定 > 一般 > 情報 > 証明書信頼設定 で完全な信頼を有効化'
    Write-Host '  4. WebRTC publish URLを開き、Basic認証とカメラ権限を許可'
    Write-Host ''
    Write-Host '停止するとFirewallルールとコンテナを自動で削除します。' -ForegroundColor Yellow
    Write-Host 'CAとサーバー証明書は次回再利用するため tmp/smartphone/ に残します。完全削除は cleanup.ps1 を使用します。'
    Write-Host ''

    Read-Host '停止するには Enter を押してください（Ctrl+Cでもfinallyで停止処理を実行します）' | Out-Null
}
finally {
    Write-Host ''
    Write-Host 'スマートフォンWebRTC検証環境を停止します。'
    try {
        Invoke-WslRepositoryCommand -Context $context -Command "${composeEnv}docker compose -f $composeFile down --remove-orphans" -IgnoreExitCode | Out-Null
    }
    catch {
        Write-Warning "Docker Compose停止処理でエラーが発生しました: $($_.Exception.Message)"
    }

    if (-not $SkipFirewall) {
        try {
            Remove-SmartphoneFirewallRules
            Write-Host 'Windows Firewallの一時ルールを削除しました。'
        }
        catch {
            Write-Warning "Firewallルール削除でエラーが発生しました: $($_.Exception.Message)"
        }
    }

    if ($composeStarted -or $firewallAdded) {
        Write-Host '停止処理が完了しました。' -ForegroundColor Green
    }
}
