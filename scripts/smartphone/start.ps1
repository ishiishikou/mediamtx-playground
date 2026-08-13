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
$publishUrl = "https://${LanIp}:8889/live/iphone-001/publish"
$viewerUrl = "https://${LanIp}:8889/live/iphone-001"

try {
    Write-Host "[1/7] WSL/Dockerを確認します: $($context.RepoPath)"
    Invoke-WslRepositoryCommand -Context $context -Command 'docker version >/dev/null && docker compose version >/dev/null' | Out-Null

    Write-Host '[2/7] 前回のコンテナとFirewallルールを掃除します。'
    Invoke-WslRepositoryCommand -Context $context -Command "${composeEnv}docker compose -f $composeFile down --remove-orphans >/dev/null 2>&1 || true" -IgnoreExitCode | Out-Null
    if (-not $SkipFirewall) {
        Remove-SmartphoneFirewallRules
    }

    Write-Host '[3/7] 検証用workspaceとmkcertコンテナを準備します。'
    Invoke-WslRepositoryCommand -Context $context -Command 'sh scripts/smartphone/ensure-workspace.sh tmp/smartphone' | Out-Null
    Invoke-WslRepositoryCommand -Context $context -Command "${composeEnv}docker compose -f $composeFile build cert-generator" | Out-Null

    Write-Host "[4/7] 検証用CAを準備し、${LanIp} 向けサーバー証明書を生成します。"
    Invoke-WslRepositoryCommand -Context $context -Command "${composeEnv}docker compose -f $composeFile run --rm cert-generator" | Out-Null
    Invoke-WslRepositoryCommand -Context $context -Command "${composeEnv}docker compose -f $composeFile run --rm --no-deps --entrypoint qrencode cert-generator -o /work/public/publish-qr.png -s 8 -m 4 '$publishUrl'" | Out-Null

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

    Write-Host '[7/7] 公開ポートの起動状態を確認します。'
    $localCaReady = $false
    $localHttpsReady = $false
    for ($attempt = 1; $attempt -le 10; $attempt++) {
        $localCaReady = Test-NetConnection -ComputerName 127.0.0.1 -Port 8000 -InformationLevel Quiet -WarningAction SilentlyContinue
        $localHttpsReady = Test-NetConnection -ComputerName 127.0.0.1 -Port 8889 -InformationLevel Quiet -WarningAction SilentlyContinue
        if ($localCaReady -and $localHttpsReady) {
            break
        }
        Start-Sleep -Seconds 1
    }

    if (-not $localCaReady -or -not $localHttpsReady) {
        throw @"
Windows localhostからDocker公開ポートへ到達できませんでした。
  127.0.0.1:8000 = $localCaReady
  127.0.0.1:8889 = $localHttpsReady
Docker/WSL側のコンテナ起動状態とport publishを確認してください。
Firewallとコンテナはfinallyで自動的に元へ戻します。
"@
    }

    $lanCaReady = Test-NetConnection -ComputerName $LanIp -Port 8000 -InformationLevel Quiet -WarningAction SilentlyContinue
    $lanHttpsReady = Test-NetConnection -ComputerName $LanIp -Port 8889 -InformationLevel Quiet -WarningAction SilentlyContinue
    if ($lanCaReady -and $lanHttpsReady) {
        Write-Host "Windows LAN IP自己疎通: ${LanIp}:8000 / :8889 OK" -ForegroundColor Green
    }
    else {
        Write-Warning @"
Windows自身からLAN IP ($LanIp) へのTCP自己疎通は確認できませんでした。
  ${LanIp}:8000 = $lanCaReady
  ${LanIp}:8889 = $lanHttpsReady

WSL mirrored networking等では、Windows自身からLAN IPへの接続が失敗しても、同一LANのスマートフォンから到達できる場合があります。
この結果だけでは環境を停止しません。下に表示するCA取得URLとWebRTC publish URLをスマートフォンから開いて到達性を確認してください。
"@
    }

    Write-Host ''
    Write-Host 'スマートフォンWebRTC検証環境を起動しました。' -ForegroundColor Green
    Write-Host "LAN IP              : $LanIp"
    Write-Host "CA取得URL            : http://${LanIp}:8000/rootCA.pem"
    Write-Host "WebRTC publish URL   : $publishUrl"
    Write-Host "WebRTC viewer URL    : $viewerUrl"
    Write-Host 'publisher user       : poc-publisher'
    Write-Host 'publisher password   : poc-publisher-pass'
    Write-Host ''
    Write-Host 'Publish URLのQRコードをPCのブラウザで表示します。'
    Start-Process 'http://127.0.0.1:8000/publish-qr.png'
    Write-Host ''
    Write-Host 'iPhone初回のみ:'
    Write-Host '  1. CA取得URLをSafariで開いてrootCA.pemを取得'
    Write-Host '  2. 設定 > ダウンロード済みのプロファイル からCAをインストール'
    Write-Host '  3. 設定 > 一般 > 情報 > 証明書信頼設定 で完全な信頼を有効化'
    Write-Host '  4. QRコードからWebRTC publish URLを開き、Basic認証とカメラ権限を許可'
    Write-Host ''
    Write-Host '停止するとFirewallルールとコンテナを自動で削除します。' -ForegroundColor Yellow
    Write-Host 'CAは次回再利用するため tmp/smartphone/ に残します。完全削除は cleanup.ps1 を使用します。'
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
