function ChromeDriverAndEventGhostCheck {
    [CmdletBinding()]
    Param ()

    #if (!$(Get-Module -ListAvailable Selenium -ErrorAction SilentlyContinue)) {Install-Module Selenium}
    #if (!$(Get-Module Selenium -ErrorAction SilentlyContinue)) {Import-Module Selenium}

    # Check for chromedriver.exe
    if (!$(Get-Command chromedriver.exe -ErrorAction SilentlyContinue)) {
        try {
            SeleniumDriverSetup -ErrorAction Stop
        } catch {
            Write-Error $_
            return
        }
    }

    # Make sure EventGhost is setup
    try {
        $EventGhostProcess = Get-Process eventghost -ErrorAction SilentlyContinue
        if ($EventGhostProcess) {
            # Determine if the correct configuration file is loaded
            if (!$($EventGhostProcess.MainWindowTitle -match 'eventghosttreett')) {
                # Kill EventGhost if it is running
                $null = $EventGhostProcess | Stop-Process -ErrorAction SilentlyContinue
            }
        }

        SetupEventGhost

    } catch {
        Write-Error $_
        return
    }

}
