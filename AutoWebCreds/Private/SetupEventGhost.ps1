function SetupEventGhost {
    [CmdletBinding()]
    param()

    if (!$(Get-Command EventGhost.exe)) {
        # First, see if it's installed but just not part og $env:Path
        $EventGhostPath = 'C:\Program Files (x86)\EventGhost\EventGhost.exe'
        if (Test-Path $EventGhostPath) {
            try {
                $null = AddPath -PathToAdd $EventGhostPath -UpdateSystemPath
            } catch {
                Write-Error $_
                return
            }
        } else {
            # Need to install EventGhost
            try {
                InstallEventGhost
            } catch {
                Write-Error $_
                return
            }

            if (!$(Test-Path $EventGhostPath)) {
                try {
                    $null = AddPath -PathToAdd $EventGhostPath -UpdateSystemPath
                } catch {
                    Write-Error $_
                    return
                }
            }
        }
    }

    # Start EventGhost with the appropriate configuration file (and install referenced plugins if necessary)
    $PluginParentDir = 'C:\Program Files (x86)\EventGhost\plugins'
    $PluginsToCheckFor = @('AutoRemote','TextGrab','TCPEvents')
    $PluginsToCheckFor | foreach {
        $PluginDirPath = $PluginParentDir + '\' + $_
        if (!$(Test-Path $PluginDirPath)) {
            $ModulePluginPath = $PSScriptRoot + '\' + 'EventGhost' + '\' + 'Plugins' + '\' + $_
            try {
                $null = Copy-Item -Path $ModulePluginPath -Destination $PluginDirPath -Force
            } catch {
                Write-Error $_
                return
            }
        }
    }

    $EventGhostConfigFile = $PSScriptRoot + '\' + 'EventGhost' + '\' + 'ConfigurationFiles' + '\' + 'eventghosttreett.xml'
    & $EventGhostPath -file $EventGhostConfigFile
}
