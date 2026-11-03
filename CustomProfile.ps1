# Powershell environment specific procedures
switch ($PSVersionTable.PSEdition)
{
    'Core'
    {
        'Detected PowerShell Core' | Write-Verbose

        oh-my-posh init pwsh --config (Join-Path $CachePath 'getps_ohmyposh.json') | Invoke-Expression

        try
        {
            Import-Module -Name Terminal-Icons -ErrorAction Stop
        }
        catch
        {
            Write-Warning "Terminal-Icons could not be loaded: $($_.Exception.Message)"
        }

        Set-PSReadLineOption -PredictionSource History
        Set-PSReadLineOption -EditMode Windows
        'Set PSReadLine options: PredictionSource=History, EditMode=Windows' | Write-Verbose

        # This setting is only available in in 2.2.0-beta4
        if ((Get-Module psreadline | Select-Object -ExpandProperty version) -ge '2.2.0.0')
        {
            Set-PSReadLineOption -PredictionViewStyle ListView
            'Set PSReadLine option: PredictionViewStyle=ListView' | Write-Verbose
        }
    }
    'Desktop'
    {
        oh-my-posh init powershell --config (Join-Path $CachePath 'getps_ohmyposh.json') | Invoke-Expression
    }
}

# Turn on information messages for the rest of the profile
$global:InformationPreference = 'Continue'
"Configured global InformationPreference to 'Continue'" | Write-Verbose

# This is a test
