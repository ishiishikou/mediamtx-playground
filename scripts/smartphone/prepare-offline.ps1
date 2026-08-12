[CmdletBinding()]
param(
    [string]$Distro
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

$repositoryRoot = Get-SmartphoneRepositoryRoot
$context = Get-WslRepositoryContext -RepositoryRoot $repositoryRoot -Distro $Distro
$composeFile = 'examples/docker-compose.smartphone.yml'
$composeEnv = 'export SMARTPHONE_UID=$(id -u); export SMARTPHONE_GID=$(id -g); '

Write-Host "[1/3] WSL/Dockerを確認します: $($context.RepoPath)"
Invoke-WslRepositoryCommand -Context $context -Command 'docker version >/dev/null && docker compose version >/dev/null' | Out-Null

Write-Host '[2/3] オフライン実行に必要なDockerイメージを取得します。'
Invoke-WslRepositoryCommand -Context $context -Command "${composeEnv}docker compose -f $composeFile pull mediamtx cert-server" | Out-Null

Write-Host '[3/3] 証明書生成用イメージを事前buildします。'
Invoke-WslRepositoryCommand -Context $context -Command "${composeEnv}docker compose -f $composeFile build cert-generator" | Out-Null

Write-Host ''
Write-Host 'オフライン実機検証の事前準備が完了しました。' -ForegroundColor Green
Write-Host 'このPCをインターネットから切断した後でも、取得済みイメージを使ってスマートフォンWebRTC検証を開始できます。'
Write-Host 'Windowsのモバイルホットスポットを有効化してスマートフォンを接続し、start.ps1を実行してください。'
