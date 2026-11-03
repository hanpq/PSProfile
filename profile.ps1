# Install this bootstrapper as $PROFILE.CurrentUserAllHosts on each computer.
# A local copy loads immediately; an update is staged for a later shell.
# The next shell reports '[profile] updated' once after loading a staged update.
$CachePath = Join-Path $env:USERPROFILE '.cache\psprofile'
$RemoteUri = 'https://raw.githubusercontent.com/hanpq/PSProfile/refs/heads/main/'
$Files = @('CustomProfile.ps1', 'getps_ohmyposh.json', 'terminal_settings.json')
$Pointer = Join-Path $CachePath 'current.txt'
$Attempt = Join-Path $CachePath 'last-attempt.txt'

$UpdateProfile = {
    param($CachePath, $RemoteUri, $Files, [bool]$Force)

    $lock = $null
    $stage = $null
    $temporaryPointer = $null
    try
    {
        $lockPath = Join-Path $CachePath 'update.lock'
        for ($i = 0; $i -lt $(if ($Force)
                {
                    150 
                }
                else
                {
                    1 
                }); $i++)
        {
            try
            {
                $lock = [IO.File]::Open($lockPath, [IO.FileMode]::OpenOrCreate,
                    [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
                break
            }
            catch [IO.IOException]
            {
                if (-not $Force)
                {
                    return 
                }
                Start-Sleep -Milliseconds 200
            }
        }
        if ($null -eq $lock)
        {
            throw 'Timed out waiting for another profile update.' 
        }

        $pointer = Join-Path $CachePath 'current.txt'
        $attempt = Join-Path $CachePath 'last-attempt.txt'
        if ($Force -and (Test-Path $pointer))
        {
            $installedVersion = (Get-Content -Raw -Path $pointer -ErrorAction Stop).Trim()
            if ($installedVersion -match '^[a-f0-9]{32}$' -and
                @($Files | Where-Object {
                        -not (Test-Path (Join-Path (Join-Path $CachePath $installedVersion) $_))
                    }).Count -eq 0)
            {
                return
            }
        }
        if (-not $Force -and (Test-Path $attempt) -and
            (Get-Item $attempt).LastWriteTimeUtc -gt [datetime]::UtcNow.AddMinutes(-1))
        {
            return
        }
        Set-Content -Path $attempt -Value ([datetime]::UtcNow.ToString('o'))

        $stage = Join-Path $CachePath ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $stage -ErrorAction Stop | Out-Null
        foreach ($file in $Files)
        {
            $destination = Join-Path $stage $file
            Invoke-WebRequest -Uri ($RemoteUri + $file) -OutFile $destination `
                -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
            Unblock-File -Path $destination -ErrorAction Stop
        }

        $parseErrors = $null
        [System.Management.Automation.Language.Parser]::ParseFile(
            (Join-Path $stage 'CustomProfile.ps1'), [ref]$null, [ref]$parseErrors) | Out-Null
        if ($parseErrors.Count -gt 0)
        {
            throw "Downloaded profile has syntax errors: $($parseErrors[0])" 
        }
        foreach ($file in $Files | Where-Object { $_ -like '*.json' })
        {
            Get-Content -Raw -Path (Join-Path $stage $file) -ErrorAction Stop |
                ConvertFrom-Json -ErrorAction Stop | Out-Null
        }

        $oldDirectory = $null
        if (Test-Path $pointer)
        {
            $oldVersion = (Get-Content -Raw -Path $pointer -ErrorAction Stop).Trim()
            if ($oldVersion -match '^[a-f0-9]{32}$')
            {
                $oldDirectory = Join-Path $CachePath $oldVersion
            }
        }
        if ($oldDirectory -and (Test-Path $oldDirectory))
        {
            $unchanged = $true
            foreach ($file in $Files)
            {
                $existing = Join-Path $oldDirectory $file
                if (-not (Test-Path $existing) -or
                    (Get-FileHash $existing).Hash -ne (Get-FileHash (Join-Path $stage $file)).Hash)
                {
                    $unchanged = $false
                    break
                }
            }
            if ($unchanged)
            {
                Remove-Item (Join-Path $CachePath 'pending-error.txt') -ErrorAction SilentlyContinue
                return
            }
        }

        $version = Split-Path $stage -Leaf
        if (-not $Force)
        {
            New-Item -ItemType File -Path (Join-Path $stage 'pending-update.txt') -ErrorAction Stop | Out-Null
        }
        $temporaryPointer = Join-Path $CachePath ("current.$version.tmp")
        Set-Content -Path $temporaryPointer -Value $version -NoNewline -ErrorAction Stop
        if (Test-Path $pointer)
        {
            [IO.File]::Replace($temporaryPointer, $pointer, (Join-Path $CachePath 'previous.txt'))
        }
        else
        {
            Move-Item -Path $temporaryPointer -Destination $pointer -ErrorAction Stop
        }
        $temporaryPointer = $null
        $stage = $null
        Remove-Item (Join-Path $CachePath 'pending-error.txt') -ErrorAction SilentlyContinue
    }
    catch
    {
        $message = "$([datetime]::Now.ToString('s')): $($_.Exception.Message)"
        try
        {
            Set-Content -Path (Join-Path $CachePath 'last-error.log') -Value $message -ErrorAction Stop
            Set-Content -Path (Join-Path $CachePath 'pending-error.txt') -Value $message -ErrorAction Stop
        }
        catch
        {
            Write-Error "Profile update failed and could not be logged: $message; $($_.Exception.Message)"
        }
        if ($Force)
        {
            Write-Warning "Profile update failed: $message" 
        }
    }
    finally
    {
        if ($temporaryPointer -and (Test-Path $temporaryPointer))
        {
            Remove-Item $temporaryPointer -Force
        }
        if ($stage -and (Test-Path $stage))
        {
            Remove-Item $stage -Recurse -Force
        }
        if ($lock)
        {
            $lock.Dispose() 
        }
    }
}

try
{
    New-Item -ItemType Directory -Path $CachePath -Force -ErrorAction Stop | Out-Null

    $currentDirectory = $null
    if (Test-Path $Pointer)
    {
        $version = (Get-Content -Raw -Path $Pointer -ErrorAction Stop).Trim()
        if ($version -match '^[a-f0-9]{32}$')
        {
            $currentDirectory = Join-Path $CachePath $version
        }
        else
        {
            Write-Warning 'Invalid local profile version; trying to recover.'
        }
    }

    # Existing installations stored the three files directly in the cache root.
    if (-not $currentDirectory -and (Test-Path (Join-Path $CachePath 'CustomProfile.ps1')))
    {
        $currentDirectory = $CachePath
    }
    $ready = $currentDirectory -and @($Files | Where-Object {
            -not (Test-Path (Join-Path $currentDirectory $_))
        }).Count -eq 0
    if (-not $ready)
    {
        Write-Host '[profile] First-time setup: downloading profile...' -ForegroundColor Cyan
        & $UpdateProfile $CachePath $RemoteUri $Files $true
        if (Test-Path $Pointer)
        {
            $version = (Get-Content -Raw -Path $Pointer -ErrorAction Stop).Trim()
            if ($version -match '^[a-f0-9]{32}$')
            {
                $currentDirectory = Join-Path $CachePath $version
            }
        }
        $ready = $currentDirectory -and @($Files | Where-Object {
                -not (Test-Path (Join-Path $currentDirectory $_))
            }).Count -eq 0
    }

    if ($ready)
    {
        $CachePath = $currentDirectory
        try
        {
            . (Join-Path $CachePath 'CustomProfile.ps1')
        }
        catch
        {
            Write-Warning "Current profile failed to load: $($_.Exception.Message)"
            $previousPointer = Join-Path (Split-Path $Pointer) 'previous.txt'
            if (-not (Test-Path $previousPointer))
            {
                throw 
            }
            $previousVersion = (Get-Content -Raw $previousPointer -ErrorAction Stop).Trim()
            if ($previousVersion -notmatch '^[a-f0-9]{32}$')
            {
                throw 
            }
            $CachePath = Join-Path (Split-Path $Pointer) $previousVersion
            if (@($Files | Where-Object {
                        -not (Test-Path (Join-Path $CachePath $_))
                    }).Count -gt 0)
            {
                throw 
            }
            . (Join-Path $CachePath 'CustomProfile.ps1')
            Write-Warning 'Loaded the previous profile version instead.'
        }
        $pendingUpdate = Join-Path $CachePath 'pending-update.txt'
        if ($CachePath -eq $currentDirectory -and (Test-Path $pendingUpdate))
        {
            Remove-Item -Path $pendingUpdate -ErrorAction Stop
            Write-Host '[profile] updated' -ForegroundColor DarkCyan
        }
        else
        {
            Write-Host '[profile] ready' -ForegroundColor DarkCyan
        }
    }
    else
    {
        Write-Warning 'No complete local profile is available. Publish the repository or restore network access, then open a new shell.'
    }

    $pendingError = Join-Path (Split-Path $Pointer) 'pending-error.txt'
    if (Test-Path $pendingError)
    {
        Write-Warning (Get-Content -Raw $pendingError)
        Remove-Item $pendingError -ErrorAction Stop
    }

    $attempt = Join-Path (Split-Path $Pointer) 'last-attempt.txt'
    if ($ready -and (-not (Test-Path $attempt) -or
            (Get-Item $attempt).LastWriteTimeUtc -le [datetime]::UtcNow.AddMinutes(-5)))
    {
        $runspace = [runspacefactory]::CreateRunspace()
        $runspace.Open()
        $pipeline = [powershell]::Create()
        $pipeline.Runspace = $runspace
        $null = $pipeline.AddScript($UpdateProfile.ToString()).
        AddArgument((Split-Path $Pointer)).
        AddArgument($RemoteUri).
        AddArgument($Files).
        AddArgument($false)
        $global:PowerShellProfileUpdate = @{
            Runspace   = $runspace
            Pipeline   = $pipeline
            Invocation = $pipeline.BeginInvoke()
        }
    }
}
catch
{
    Write-Warning "Profile startup failed: $($_.Exception.Message)"
}
