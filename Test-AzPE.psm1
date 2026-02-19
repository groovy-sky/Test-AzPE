function Resolve-DnsRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidatePattern('^(?=.{1,253}$)(?!-)[A-Za-z0-9-]{1,63}(?<!-)(\.(?!-)[A-Za-z0-9-]{1,63}(?<!-))*\.?$')]
        [string]$RecordName,

        [Parameter(Mandatory = $false)]
        [ValidateScript({
            if (-not $_) { return $true }
            return $_ -match '^(?=.{1,253}$)(?!-)[A-Za-z0-9-]{1,63}(?<!-)(\.(?!-)[A-Za-z0-9-]{1,63}(?<!-))*\.?$' -or $_ -match '^(([0-9]{1,3}\.){3}[0-9]{1,3})$'
        })]
        [string]$DnsServer,

        [Parameter(Mandatory = $false)]
        [ValidateSet('A', 'AAAA', 'CNAME', 'MX', 'NS', 'SRV', 'TXT', 'PTR', 'SOA')]
        [string]$RecordType = 'A'
    )

    try {
        [string]$ServerToUse = $DnsServer

        if (-not $ServerToUse) {
            $DefaultServer = Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                Where-Object { $_.ServerAddresses } |
                Select-Object -ExpandProperty ServerAddresses -First 1
            $ServerToUse = $DefaultServer
        }

        if ($ServerToUse) {
            Write-Verbose "Resolving '$RecordName' type '$RecordType' via server '$ServerToUse'."
            $response = Resolve-DnsName -Name $RecordName -Server $ServerToUse -Type $RecordType -ErrorAction Stop
        }
        else {
            Write-Verbose "Resolving '$RecordName' type '$RecordType' using system default DNS (no server override)."
            $response = Resolve-DnsName -Name $RecordName -Type $RecordType -ErrorAction Stop
        }

        # Project key fields; adjust as needed for other record types
        $answers = $response | ForEach-Object {
            [PSCustomObject]@{
                Name       = $_.Name
                Type       = $_.Type
                Data       = ($_.IPAddress, $_.NameHost, $_.Strings, $_.Mailbox, $_.Target) -ne $null | Select-Object -First 1
                TTL        = $_.TTL
                Section    = $_.Section
                NameServer = $_.NameServer
            }
        }

        [PSCustomObject]@{
            RecordName = $RecordName
            RecordType = $RecordType
            DnsServer  = $ServerToUse
            IsSuccess  = $true
            Answers    = $answers
        }
    }
    catch {
        Write-Error -ErrorRecord $_
        [PSCustomObject]@{
            RecordName = $RecordName
            RecordType = $RecordType
            DnsServer  = $ServerToUse
            IsSuccess  = $false
            Answers    = @()
            Error      = $_.Exception.Message
        }
    }
}

function Test-AzPE {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidatePattern('^(?=.{1,253}$)(?!-)[A-Za-z0-9-]{1,63}(?<!-)(\.(?!-)[A-Za-z0-9-]{1,63}(?<!-))*\.?$')]
        [string]$RecordName,

        [Parameter(Mandatory = $true)]
        [ValidatePattern('^(([0-9]{1,3}\.){3}[0-9]{1,3})$')]
        [string]$InternalDnsServer,

        [Parameter(Mandatory = $false)]
        [ValidateSet('A', 'AAAA', 'CNAME', 'MX', 'NS', 'SRV', 'TXT', 'PTR', 'SOA')]
        [string]$RecordType = 'A'
    )

    [string]$PublicDnsServer = '1.1.1.1'
    [string]$PrivateRangePattern = '^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[0-1])\.)'
    [bool]$isVerbose = $PSBoundParameters.ContainsKey('Verbose')

    $commonParams = @{
        RecordName = $RecordName
        RecordType = $RecordType
    }

    if ($isVerbose) {
        $commonParams['Verbose'] = $true
    }

    $emit = {
        param($obj)
        if (-not $isVerbose) {
            return $obj.StatusMessage
        }
        return $obj
    }

    Write-Verbose "Testing internal DNS '$InternalDnsServer' for '$RecordName' ($RecordType)."
    $internalResult = Resolve-DnsRecord @commonParams -DnsServer $InternalDnsServer

    $internalIp = $internalResult.Answers |
        Where-Object { $_.Type -in @('A', 'AAAA') -and $_.Data } |
        Select-Object -ExpandProperty Data -First 1

    $internalIsPrivate = $internalIp -and ($internalIp -match $PrivateRangePattern)

    if ($internalIp -and $internalIsPrivate) {
        $result = [PSCustomObject]@{
            RecordName             = $RecordName
            RecordType             = $RecordType
            StatusMessage          = "Private endpoint is configured and resolves through $InternalDnsServer"
            StatusCode             = 'PrivateEndpointHealthy'
            ResolutionSource       = 'Internal'
            InternalDnsServer      = $InternalDnsServer
            Address                = $internalIp
            InternalIsPrivateRange = $true
            InternalResolution     = $internalResult
        }
        return & $emit $result
    }

    Write-Verbose "Internal DNS resolution failed or no private address found; attempting public lookups via '$PublicDnsServer'."
    $publicCnameResult = Resolve-DnsRecord -RecordName $RecordName -RecordType 'CNAME' -DnsServer $PublicDnsServer -Verbose:$isVerbose
    $publicAResult = Resolve-DnsRecord -RecordName $RecordName -RecordType 'A' -DnsServer $PublicDnsServer -Verbose:$isVerbose

    $cnameAliases = $publicCnameResult.Answers |
        Where-Object { $_.Type -eq 'CNAME' -and $_.Data } |
        Select-Object -ExpandProperty Data

    $cnameTarget = $cnameAliases | Select-Object -First 1
    $privateLinkAliases = $cnameAliases | Where-Object { $_ -match '\.privatelink\.' }
    $hasPrivateLinkAlias = $privateLinkAliases.Count -gt 0

    $publicIp = $publicAResult.Answers |
        Where-Object { $_.Type -eq 'A' -and $_.Data } |
        Select-Object -ExpandProperty Data -First 1

    # Decision matrix
    if ($internalIp -and -not $internalIsPrivate) {
        if (-not $hasPrivateLinkAlias) {
            $result = [PSCustomObject]@{
                RecordName             = $RecordName
                RecordType             = $RecordType
                StatusMessage          = 'No private endpoint configured'
                StatusCode             = 'NoPrivateEndpoint'
                InternalDnsServer      = $InternalDnsServer
                PublicDnsServer        = $PublicDnsServer
                InternalAddress        = $internalIp
                InternalIsPrivateRange = $false
                HasPrivateLinkAlias    = $hasPrivateLinkAlias
                CnameAliases           = $cnameAliases
                PrivateLinkAliases     = $privateLinkAliases
                PrivateLinkAliasCount  = $privateLinkAliases.Count
                InternalResolution     = $internalResult
                PublicCnameResolution  = $publicCnameResult
                PublicAResolution      = $publicAResult
                PublicAddress          = $publicIp
            }
            return & $emit $result
        }
    }

    if (-not $internalIp -and $publicIp -and $hasPrivateLinkAlias) {
        $result = [PSCustomObject]@{
            RecordName            = $RecordName
            RecordType            = $RecordType
            StatusMessage         = "Private endpoint misconfiguration: $InternalDnsServer did not return a private endpoint IP from its private DNS zone"
            StatusCode            = 'PrivateEndpointMissingInPrivateDNS'
            InternalDnsServer     = $InternalDnsServer
            PublicDnsServer       = $PublicDnsServer
            HasPrivateLinkAlias   = $hasPrivateLinkAlias
            CnameAliases          = $cnameAliases
            PrivateLinkAliases    = $privateLinkAliases
            PrivateLinkAliasCount = $privateLinkAliases.Count
            InternalResolution    = $internalResult
            PublicCnameResolution = $publicCnameResult
            PublicAResolution     = $publicAResult
            PublicAddress         = $publicIp
        }
        return & $emit $result
    }

    if (-not $internalIp -and -not $publicIp) {
        $result = [PSCustomObject]@{
            RecordName            = $RecordName
            RecordType            = $RecordType
            StatusMessage         = 'Record does not exist'
            StatusCode            = 'NotFound'
            InternalDnsServer     = $InternalDnsServer
            PublicDnsServer       = $PublicDnsServer
            HasPrivateLinkAlias   = $hasPrivateLinkAlias
            CnameAliases          = $cnameAliases
            PrivateLinkAliases    = $privateLinkAliases
            PrivateLinkAliasCount = $privateLinkAliases.Count
            InternalResolution    = $internalResult
            PublicCnameResolution = $publicCnameResult
            PublicAResolution     = $publicAResult
        }
        return & $emit $result
    }

    $result = [PSCustomObject]@{
        RecordName            = $RecordName
        RecordType            = $RecordType
        StatusMessage         = 'No private endpoint configured'
        StatusCode            = 'NoPrivateEndpoint'
        InternalDnsServer     = $InternalDnsServer
        PublicDnsServer       = $PublicDnsServer
        InternalAddress       = $internalIp
        InternalIsPrivateRange = $internalIsPrivate
        HasPrivateLinkAlias   = $hasPrivateLinkAlias
        CnameAliases          = $cnameAliases
        PrivateLinkAliases    = $privateLinkAliases
        PrivateLinkAliasCount = $privateLinkAliases.Count
        InternalResolution    = $internalResult
        PublicCnameResolution = $publicCnameResult
        PublicAResolution     = $publicAResult
        PublicAddress         = $publicIp
    }
    return & $emit $result
}

Set-Alias -Name Test-DnsPE -Value Test-AzPE -Option AllScope
Export-ModuleMember -Function Resolve-DnsRecord, Test-AzPE -Alias Test-DnsPE