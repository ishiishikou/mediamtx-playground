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
    return $root.ProviderPath
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

function Test-PrivateIPv4 {
    param([Parameter(Mandatory = $true)][string]$Address)

    $parsed = $null
    if (-not [System.Net.IPAddress]::TryParse($Address, [ref]$parsed) -or
        $parsed.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) {
        return $false
    }

    $bytes = $parsed.GetAddressBytes()
    if ($bytes[0] -eq 10) {
        return $true
    }
    if ($bytes[0] -eq 172 -and $bytes[1] -ge 16 -and $bytes[1] -le 31) {
        return $true
    }
    if ($bytes[0] -eq 192 -and $bytes[1] -eq 168) {
        return $true
    }
    return $false
}

function Get-UsableIPv4Candidates {
    $configs = Get-NetIPConfiguration |
        Where-Object {
            $_.NetAdapter.Status -eq 'Up' -and
            $null -ne $_.IPv4Address -and
            $_.InterfaceAlias -notmatch 'vEthernet|WSL|Docker|Loopback|Tailscale|ZeroTier'
        }

    $candidates = foreach ($config in $configs) {
        $interface = Get-NetIPInterface -InterfaceIndex $config.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
        $metric = if ($null -eq $interface) { 99999 } else { [int]$interface.InterfaceMetric }
        $description = [string]$config.NetAdapter.InterfaceDescription
        foreach ($address in $config.IPv4Address) {
            if ($address.IPAddress -match '^127\.' -or $address.IPAddress -match '^169\.254\.') {
                continue
            }

            [pscustomobject]@{
                Address = $address.IPAddress
                Metric = $metric
                HasDefaultGateway = $null -ne $config.IPv4DefaultGateway
                InterfaceAlias = [string]$config.InterfaceAlias
                InterfaceDescription = $description
                IsPrivate = Test-PrivateIPv4 -Address $address.IPAddress
                LooksLikeHotspot = (
                    $description -match 'Wi-Fi Direct|Hosted Network|Mobile Hotspot' -or
                    $config.InterfaceAlias -match 'Local Area Connection\*|ローカル エリア接続\*'
                )
            }
        }
    }

    return @($candidates)
}

function Get-PreferredLanIPv4 {
    $candidates = Get-UsableIPv4Candidates

    $selected = $candidates |
        Where-Object { $_.HasDefaultGateway } |
        Sort-Object Metric |
        Select-Object -First 1
    if ($null -ne $selected) {
        return $selected.Address
    }

    # PCがインターネット未接続でWindows Mobile Hotspotだけを提供している場合、
    # hotspot側NICにはデフォルトゲートウェイが付かないため、専用のフォールバックを使う。
    $hotspotCandidates = @($candidates |
        Where-Object { $_.IsPrivate -and $_.LooksLikeHotspot } |
        Sort-Object Metric)
    if ($hotspotCandidates.Count -eq 1) {
        return $hotspotCandidates[0].Address
    }
    if ($hotspotCandidates.Count -gt 1) {
        $addresses = ($hotspotCandidates | ForEach-Object { "$($_.InterfaceAlias)=$($_.Address)" }) -join ', '
        throw "モバイルホットスポット候補が複数あります: $addresses。-LanIp で使用するIPv4アドレスを明示してください。"
    }

    # OSやドライバーによってhotspot用NIC名が異なる場合に備え、
    # private IPv4が1つだけなら安全にフォールバックする。複数なら推測しない。
    $privateCandidates = @($candidates |
        Where-Object { $_.IsPrivate } |
        Sort-Object Metric)
    if ($privateCandidates.Count -eq 1) {
        return $privateCandidates[0].Address
    }
    if ($privateCandidates.Count -gt 1) {
        $addresses = ($privateCandidates | ForEach-Object { "$($_.InterfaceAlias)=$($_.Address)" }) -join ', '
        throw "デフォルトゲートウェイのないプライベートIPv4候補が複数あります: $addresses。-LanIp で使用するIPv4アドレスを明示してください。"
    }

    throw 'LANまたはモバイルホットスポットのIPv4アドレスを検出できませんでした。ホットスポットを有効化するか、-LanIp で明示してください。'
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
