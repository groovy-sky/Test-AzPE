# Test-AzPE Module

![](logo.svg)


## Introduction
Azure Private Endpoints only work when your workloads (VMs, apps, on-prem clients) can resolve the service’s normal public FQDN (for example, `mystorage.blob.core.windows.net`) to the **private IP address** of the private endpoint. If DNS returns a public IP (or no record), traffic won’t use the Private Endpoint.

This repository provides a PowerShell module (`Test-AzPE`) that helps to troubleshoot **Azure Private Endpoints** by validating  how it resolves against different **DNS resolves**.

## How it works
Module compares responses from internal and public DNS. For correctly configured environment internal DNS returns private IP and public DNS returns public IP.


## Usage
At first, install the script:

```powershell
Install-Script -Name Test-AzPE -Force
```

Next, test a private endpoint DNS resolution using internal DNS resolver:
```powershell
Test-AzPE -RecordName 'some-domain.azurewebsites.net' -InternalDnsServer '1.2.3.4'
```

If needed add -Verbose flage for detailed output:
```powershell
Test-AzPE -RecordName 'some-domain.azurewebsites.net' -InternalDnsServer '1.2.3.4' -Verbose
```

## Possible outcomes
- Private endpoint is configured and resolves through <internal DNS>
- No private endpoint configured
- Private endpoint misconfiguration: <internal DNS> did not return a private endpoint IP from its private DNS zone
- Record does not exist

## Summary
`Test-AzPE` is a DNS-focused health check for Azure Private Endpoints. It helps you quickly determine whether name resolution is correctly returning a private endpoint IP from your internal DNS, and if not, whether you’re dealing with a missing/incorrect private DNS integration versus a non-existent record.
## What for this module?

Quickly checks if a PaaS FQDN resolves through its Private Endpoint instead of public DNS by comparing internal and public lookups. Confirms private IP success, flags public resolution, and spots private-link aliases that are not returning private IPs.
