Set-StrictMode -Version Latest

$script:SmartphoneTcpRuleName = 'MediaMTX Smartphone Test TCP'
$script:SmartphoneUdpRuleName = 'MediaMTX Smartphone Test UDP'

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-SmartphoneRepositoryRoot {
    $root = Resolve-Path (Join-Path $PSScriptRoot '..\..')
    return $root.Path
}

function Get-WslRepositoryContext {
    param(
        [Parameter(Mandatory = $true)][string]$RepositoryRoot,
        [string]$Distro
    )

    if ($RepositoryRoot -match '^\\\\wsl(?:\.localhost|\$)\\([^\\]+)\\(.+)$') {
        $detectedDistro = $Matches[1]
        if (-not [string]::IsNullOrWhiteSpace($Distro) -and $Distro -ne $detectedDistro) {
            throw "リポジトリはWSL distro '$detectedDistro' にありますが、-Distro '$Distro' が指定されました。"
        }
        $Distro = $detectedDistro
        $linuxPath = '/' + ($Matches[2] -replace '\\', '/')
    }
    else {
        $args = @()
        if (-not [string]::IsNullOrWhiteSpace($Distro)) {
            $args += @('--distribution', $Distro)
        }
        $args += @('--exec', 'wslpath', '-a', '-u', $RepositoryRoot)
        $linuxPath = (& wsl.exe @args | Select-Object -First 1).Trim()
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($linuxPath)) {
            throw "WSL内のリポジトリパスへ変換できませんでした: $RepositoryRoot"
        }
    }

    return [pscustomobject]@{
        Distro = $Distro
        RepoPath = $linuxPath
    }
}

function Invoke-WslRepositoryCommand {
    param(
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)][string]$Command,
        [switch]$IgnoreExitCode
    )

    $args = @()
    if (-not [string]::IsNullOrWhiteSpace($Context.Distro)) {
        $args += @('--distribution', $Context.Distro)
    }
    $args += @('--cd', $Context.RepoPath, '--exec', 'bash', '-lc', $Command)

    & wsl.exe @args
    $exitCode = $LASTEXITCODE
    if (-not $IgnoreExitCode -and $exitCode -ne 0) {
        throw "WSL command failed with exit code ${exitCode}: $Command"
    }
    return $exitCode
}

function Get-PreferredLanIPv4 {
    $configs = Get-NetIPConfiguration |
        Where-Object {
            $_.NetAdapter.Status -eq 'Up' -and
            $null -ne $_.IPv4DefaultGateway -and
            $null -ne $_.IPv4Address -and
            $_.InterfaceAlias -notmatch 'vEthernet|WSL|Docker|Loopback|Tailscale|ZeroTier'
        }

    $candidates = foreach ($config in $configs) {
        $metric = (Get-NetIPInterface -InterfaceIndex $config.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).InterfaceMetric
        foreach ($address in $config.IPv4Address) {
            if ($address.IPAddress -notmatch '^127\.' -and $address.IPAddress -notmatch '^169\.254\.') {
                [pscustomobject]@{
                    Address = $address.IPAddress
                    Metric = if ($null -eq $metric) { 99999 } else { [int]$metric }
                }
            }
        }
    }

    $selected = $candidates | Sort-Object Metric | Select-Object -First 1
    if ($null -eq $selected) {
        throw 'デフォルトゲートウェイを持つLAN IPv4アドレスを検出できませんでした。-LanIp で明示してください。'
    }
    return $selected.Address
}

function Assert-IPv4Address {
    param([Parameter(Mandatory = $true)][string]$Address)

    $parsed = $null
    if (-not [System.Net.IPAddress]::TryParse($Address, [ref]$parsed) -or
        $parsed.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) {
        throw "IPv4アドレスとして解釈できません: $Address"
    }
}

function Remove-SmartphoneFirewallRules {
    foreach ($name in @($script:SmartphoneTcpRuleName, $script:SmartphoneUdpRuleName)) {
        Get-NetFirewallRule -DisplayName $name -ErrorAction SilentlyContinue |
            Remove-NetFirewallRule -ErrorAction SilentlyContinue
    }
}

function Add-SmartphoneFirewallRules {
    Remove-SmartphoneFirewallRules

    New-NetFirewallRule `
        -DisplayName $script:SmartphoneTcpRuleName `
        -Direction Inbound `
        -Action Allow `
        -Protocol TCP `
        -LocalPort 8000,8889 `
        -RemoteAddress LocalSubnet `
        -Profile Any | Out-Null

    New-NetFirewallRule `
        -DisplayName $script:SmartphoneUdpRuleName `
        -Direction Inbound `
        -Action Allow `
        -Protocol UDP `
        -LocalPort 8189 `
        -RemoteAddress LocalSubnet `
        -Profile Any | Out-Null
}
