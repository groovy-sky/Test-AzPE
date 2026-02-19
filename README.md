# Test-AzPE Module

![](logo.svg)

PowerShell module for validating Azure Private Endpoint DNS resolution.

## What for this module?

Quickly checks if a PaaS FQDN resolves through its Private Endpoint instead of public DNS by comparing internal and public lookups. Confirms private IP success, flags public resolution, and spots private-link aliases that are not returning private IPs.

## Installation

1. Install the script:

```powershell
Install-Script -Name Test-AzPE -Force
```

## Usage

Test a private endpoint DNS resolution using internal DNS resolver:
```powershell
Test-AzPE -RecordName 'some-domain.azurewebsites.net' -InternalDnsServer '1.2.3.4'
```

Get detailed diagnostics:
```powershell
Test-AzPE -RecordName 'some-domain.azurewebsites.net' -InternalDnsServer '1.2.3.4' -Verbose
```

## Expected outcomes (status messages)
- Private endpoint is configured and resolves through <internal DNS>
- No private endpoint configured
- Private endpoint misconfiguration: <internal DNS> did not return a private endpoint IP from its private DNS zone
- Record does not exist

