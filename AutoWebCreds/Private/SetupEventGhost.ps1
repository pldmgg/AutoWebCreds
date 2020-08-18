function InstallEventGhost {
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
    $PluginsToCheckFor = @('AutoRemote','TextGrab','TCPEvents')
    

}
