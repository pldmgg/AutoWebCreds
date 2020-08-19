function AmazonMusicSeleniumLoginCheck {
    [CmdletBinding()]
    param(
        [parameter(Mandatory=$false)]
        [ValidatePattern('[0-9]')]
        $ChromeProfileNumber = '0'
    )

    $ServiceName = "AmazonMusic"
    $SiteUrl = "https://music.amazon.com/home"

    $ChromeUserData = "$HOME\AppData\Local\Google\Chrome\User Data"
    $AvailableProfiles = $(Get-ChildItem -Path $ChromeUserData -Directory -Filter "Profile *").Name
    $ProfileDirName = 'Profile ' + $ChromeProfileNumber
    $ChromeProfile = @($AvailableProfiles) -match $ProfileDirName
    if (!$ChromeProfile) {
        Write-Error "Unable to find Chrome Profile '$ProfileDirName'. Halting!"
        return
    }

    # Make sure we can connect to the Url
    try {
        $HttpClient = [System.Net.Http.HttpClient]::new()
        $HttpClient.Timeout = [timespan]::FromSeconds(10)
        $HttpResponse = $HttpClient.GetAsync($SiteUrl)
        
        $i = 0
        while ($(-not $HttpResponse.IsCompleted) -and $i -lt 10) {
            Start-Sleep -Seconds 1
            $i++
        }

        if ($HttpResponse.Status.ToString() -eq "Canceled") {
            throw "Cannot connect to '$SiteUrl'! Halting!"
        }

    } catch {
        Write-Error $_
        return
    }

    try {
        $null = ChromeDriverAndEventGhostCheck -ErrorAction Stop
    } catch {
        Write-Error $_
    }

    try {
        $Driver = Start-SeChrome -Arguments @("window-size=1200x600", "user-data-dir=$ChromeUserData", "profile-directory=$ChromeProfile")
        # The below Tab + Enter will clear either the "Chrome was not shutdown properly" message or the "Chrome is being controlled by automated software" message
        #[OpenQA.Selenium.Interactions.Actions]::new($Driver).SendKeys([OpenQA.Selenium.Keys]::Tab).Perform()
        #[OpenQA.Selenium.Interactions.Actions]::new($Driver).SendKeys([OpenQA.Selenium.Keys]::Enter).Perform()
        & "C:\Program Files (x86)\EventGhost\EventGhost.exe" -event ClearChromeRestoreMsg
        Enter-SeUrl $SiteUrl -Driver $Driver

        # Determine if we see a "Sign In" button. If we do, then we need to login
        $SignInButton = Get-SeElement -By XPath -Selection '//*[@id="contextMenu"]/li[1]/a' -Target $Driver
        if (!$SignInButton) {
            throw "Unable to find the SignIn button! Halting!"
        }
    } catch {
        Write-Error $_
        return
    }

    if ($SignInButton) {
        try {
            # Have the user provide Credentials
            [pscredential]$PSCreds = GetAnyBoxPSCreds -ServiceName $ServiceName
        } catch {
            Write-Error $_
            return
        }

        try {
            # We need to actually Login
            Send-SeClick -Element $SignInButton -Driver $Driver
        } catch {
            Write-Error $_
            return
        }

        ### Amazon Login ####
        try {
            $null = AmazonAccountLogin -SeleniumDriver $Driver -PSCreds $PSCreds
        } catch {
            Write-Warning $_.Exception.Message
        }

        # So we need to check the webpage for an indication that we are actually logged in now
        try {
            $SuccessfulLoginIndicator = Get-SeElement -By XPath -Selection '//*[@title="Open Play Queue"]' -Target $Driver
            if (!$SuccessfulLoginIndicator) {
                throw 'Did not successfully login with Amazon! Halting!'
            }
        } catch {
            Write-Error $_
            return
        }
    }

    $Driver

    <#
    $Driver.Close()
    $Driver.Dispose()
    #>
}