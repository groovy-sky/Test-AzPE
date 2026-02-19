@{
    RootModule        = 'Test-AzPE.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = '1b7fd2d0-25d1-4f45-9d1e-f20e2c9f0f9f'
    Author            = 'groovy-sky'
    Description       = 'Azure Private Endpoint DNS validation.'
    PowerShellVersion = '5.1'

    FunctionsToExport = @('Resolve-DnsRecord', 'Test-AzPE')
    CmdletsToExport   = @()
    AliasesToExport   = @('Test-DnsPE')
    VariablesToExport = @()

    PrivateData = @{}
}
