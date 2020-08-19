function TidalSeleniumLoginCheck {
    [CmdletBinding()]
    param(
        [parameter(Mandatory=$false)]
        [ValidatePattern('[0-9]')]
        $ChromeProfileNumber = '0'
    )

    $ServiceName = "Tidal"
    $SiteUrl = "https://listen.tidal.com/"

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
        $LoginButton = Get-SeElement -By XPath -Selection '//*[@id="sidebar"]/section[1]/button[2]' -Target $Driver
        if (!$LoginButton) {
            throw "Unable to find the SignIn button! Halting!"
        }
    } catch {
        Write-Error $_
        return
    }

    if ($LoginButton) {
        # Have the user provide Credentials
        try {
            [pscredential]$PSCreds = GetAnyBoxPSCreds -ServiceName $ServiceName
        } catch {
            Write-Error $_
            return
        }

        # We need to actually Login
        try {
            Send-SeClick -Element $SignInButton -Driver $Driver
        } catch {
            Write-Error $_
            return
        }

        <#
        ### Basic UserName and Password Login ####
        try {
            $null = TidalUserNamePwdLogin -SeleniumDriver $Driver -PSCreds $PSCreds
        } catch {
            Write-Error $_
            return
        }
        #>

        ### Login With Twitter ###
        try {
            # Get "Twitter" Button
            $TwitterButton = Get-SeElement -By XPath -Selection "//button[contains(@class, 'btn-client-twitter')]" -Target $Driver
            if (!$TwitterButton) {
                throw "Cannot find 'Twitter' button! Halting!"
            }
            Send-SeClick -Element $TwitterButton -Driver $Driver
        } catch {
            Write-Error $_
            return
        }

        # Even if the below fails, we might be okay if the Chrome Browser is already signed into a Google Account
        try {
            $null = TwitterAccountLogin -SeleniumDriver $Driver -PSCreds $PSCreds
        } catch {
            Write-Warning $_.Exception.Message
        }


        <#
        ### Login With Facebook ###
        try {
            # Get "Continue With Facebook" Link
            $ContinueWithFacebookLink = Get-SeElement -By XPath -Selection '//button[contains(@class, 'btn-client-facebook')]' -Target $SeleniumDriver
            if (!$ContinueWithFacebookLink) {
                throw "Cannot find 'Continue With Facebook' link! Halting!"
            }
            Send-SeClick -Element $ContinueWithFacebookLink -Driver $SeleniumDriver
        } catch {
            Write-Error $_
            return
        }

        try {
            $null = FacebookAccountLogin -SeleniumDriver $Driver -PSCreds $PSCreds
        } catch {
            Write-Warning $_.Exception.Message
        }


        ### Login with Apple ###
        try {
            # Get "Continue With Apple" Link
            $ContinueWithAppleLink = Get-SeElement -By XPath -Selection '//*[@id="appleid-signin"]' -Target $SeleniumDriver
            if (!$ContinueWithAppleLink) {
                throw "Cannot find 'Continue With Apple' link! Halting!"
            }
            Send-SeClick -Element $ContinueWithAppleLink -Driver $SeleniumDriver
        } catch {
            Write-Error $_
            return
        }

        try {
            $null = AppleAccountLogin -SeleniumDriver $Driver -PSCreds $PSCreds
        } catch {
            Write-Warning $_.Exception.Message
        }
        #>

        # So we need to check the webpage for an indication that we are actually logged in now
        try {
            $SuccessfulLoginIndicator = Get-SeElement -By XPath -Selection "//span[contains(text(),'My Mix')]" -Target $Driver
            if (!$SuccessfulLoginIndicator) {
                throw "Did not successfully login with $LoginService! Halting!"
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