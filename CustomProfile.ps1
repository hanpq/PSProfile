# Powershell environment specific procedures
switch ($PSVersionTable.PSEdition)
{
    'Core'
    {
        'Detected PowerShell Core' | Write-Verbose

        oh-my-posh init pwsh --config (Join-Path $CachePath 'getps_ohmyposh.json') | Invoke-Expression
        if (-not $? -or $LASTEXITCODE -ne 0)
        {
            throw 'Oh My Posh initialization failed.'
        }
        Write-Host '[profile] Applied OhMyPosh config' -ForegroundColor DarkCyan

        try
        {
            Import-Module -Name Terminal-Icons -ErrorAction Stop
            Write-Host '[profile] Loaded Terminal-Icons' -ForegroundColor DarkCyan
        }
        catch
        {
            Write-Warning "Terminal-Icons could not be loaded: $($_.Exception.Message)"
        }

        Set-PSReadLineOption -PredictionSource History -ErrorAction Stop
        Set-PSReadLineOption -EditMode Windows -ErrorAction Stop
        'Set PSReadLine options: PredictionSource=History, EditMode=Windows' | Write-Verbose

        # This setting is only available in in 2.2.0-beta4
        if ((Get-Module psreadline | Select-Object -ExpandProperty version) -ge '2.2.0.0')
        {
            Set-PSReadLineOption -PredictionViewStyle ListView -ErrorAction Stop
            'Set PSReadLine option: PredictionViewStyle=ListView' | Write-Verbose
        }
        Write-Host '[profile] Applied PSReadLine config' -ForegroundColor DarkCyan
    }
    'Desktop'
    {
        oh-my-posh init powershell --config (Join-Path $CachePath 'getps_ohmyposh.json') | Invoke-Expression
        if (-not $? -or $LASTEXITCODE -ne 0)
        {
            throw 'Oh My Posh initialization failed.'
        }
        Write-Host '[profile] Applied OhMyPosh config' -ForegroundColor DarkCyan
    }
}

# Replace stable Windows Terminal settings only when changed, preserving the previous file.
if ($env:LOCALAPPDATA)
{
    $terminalDirectory = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState'
    if (Test-Path -LiteralPath $terminalDirectory -PathType Container)
    {
        $temporarySettings = $null
        try
        {
            $terminalSource = Join-Path $CachePath 'terminal_settings.json'
            Get-Content -Raw -LiteralPath $terminalSource -ErrorAction Stop |
                ConvertFrom-Json -ErrorAction Stop | Out-Null
            $terminalDestination = Join-Path $terminalDirectory 'settings.json'
            $settingsExist = Test-Path -LiteralPath $terminalDestination -PathType Leaf
            if (-not $settingsExist -or
                (Get-FileHash -LiteralPath $terminalSource -ErrorAction Stop).Hash -ne
                (Get-FileHash -LiteralPath $terminalDestination -ErrorAction Stop).Hash)
            {
                $temporarySettings = Join-Path $terminalDirectory ("settings.$([guid]::NewGuid().ToString('N')).tmp")
                Copy-Item -LiteralPath $terminalSource -Destination $temporarySettings -ErrorAction Stop
                Unblock-File -LiteralPath $temporarySettings -ErrorAction Stop
                if ($settingsExist)
                {
                    [IO.File]::Replace($temporarySettings, $terminalDestination,
                        (Join-Path $terminalDirectory 'settings.profile-backup.json'))
                }
                else
                {
                    Move-Item -LiteralPath $temporarySettings -Destination $terminalDestination -ErrorAction Stop
                }
                $temporarySettings = $null
                Write-Host '[profile] Applied Terminal config' -ForegroundColor DarkCyan
            }
        }
        catch
        {
            Write-Warning "Terminal config could not be applied: $($_.Exception.Message)"
        }
        finally
        {
            if ($temporarySettings -and (Test-Path -LiteralPath $temporarySettings))
            {
                Remove-Item -LiteralPath $temporarySettings -ErrorAction Stop
            }
        }
    }
}

# Turn on information messages for the rest of the profile
$global:InformationPreference = 'Continue'
"Configured global InformationPreference to 'Continue'" | Write-Verbose
