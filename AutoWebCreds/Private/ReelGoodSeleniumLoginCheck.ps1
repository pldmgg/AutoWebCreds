function ReelGoodSeleniumLoginCheck {
    [CmdletBinding()]
    param(
        [parameter(Mandatory=$false)]
        [ValidatePattern('[0-9]')]
        $ChromeProfileNumber = '0'
    )

    $ServiceName = 'ReelGood'
    $SiteUrl = "https://reelgood.com"

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
        #$Driver = Start-SeFirefox
        #$ChromeOptions = [OpenQA.Selenium.Chrome.ChromeOptions]::new()
        #$ChromeOptions.AddArguments("headless")
        #$ChromeOptions.AddArguments("window-size=1200x600")
        #$ChromeOptions.AddArguments("user-data-dir=$ChromeUserData")
        #$ChromeOptions.AddArguments("profile-directory=$LindaChromeProfile")
        #$Driver = [OpenQA.Selenium.Chrome.ChromeDriver]::new($ChromeOptions)
        $Driver = Start-SeChrome -Arguments @("window-size=1200x600", "user-data-dir=$ChromeUserData", "profile-directory=$ChromeProfile")
        # The below Tab + Enter will clear either the "Chrome was not shutdown properly" message or the "Chrome is being controlled by automated software" message
        #[OpenQA.Selenium.Interactions.Actions]::new($Driver).SendKeys([OpenQA.Selenium.Keys]::Tab).Perform()
        #[OpenQA.Selenium.Interactions.Actions]::new($Driver).SendKeys([OpenQA.Selenium.Keys]::Enter).Perform()
        & "C:\Program Files (x86)\EventGhost\EventGhost.exe" -event ClearChromeRestoreMsg
        Enter-SeUrl $SiteUrl -Driver $Driver

        # Determine if we see a "Login" button. If we do, then we need to login
        $LoginButton = Get-SeElement -By LinkText -Selection 'Login' -Target $Driver
        if (!$LoginButton) {
            throw "Unable to find the Login button! Halting!"
        }
    } catch {
        Write-Error $_
        return
    }

    if ($LoginButton) {
        try {
            # Have the user provide Credentials
            [pscredential]$PSCreds = GetAnyBoxPSCreds -ServiceName $ServiceName
        } catch {
            Write-Error $_
            return
        }

        try {
            # We need to actually Login
            Send-SeClick -Element $LoginButton -Driver $Driver
        } catch {
            Write-Error $_
            return
        }

        <#
        ### Basic UserName and Password Login ####
        try {
            $null = ReelGoodUserNamePwdLogin -SeleniumDriver $Driver -PSCreds $PSCreds
        } catch {
            Write-Warning $_.Exception.Message
        }
        #>

        ### Login With Google ###
        try {
            # Next click, the "Login with Google" button
            $LoginWithGoogleButton = Get-SeElement -By XPath -Selection '//*[@id="modal_mountpoint"]/div/div/div[2]/div[1]/a[2]/button' -Target $Driver
            if (!$LoginWithGoogleButton) {
                throw "Cannot find 'Login With Google' button! Halting!"
            }
            Send-SeClick -Element $LoginWithGoogleButton -Driver $Driver
        } catch {
            Write-Error $_
            return
        }

        # Even if the below fails, we might be okay if the Chrome Browser is already signed into a Google Account
        try {
            $null = GoogleAccountLogin -SeleniumDriver $Driver -PSCreds $PSCreds
        } catch {
            Write-Warning $_.Exception.Message
        }

        <#
        ### Login With Facebook ###
        try {
            # Get "Continue With Facebook" Link
            $ContinueWithFacebookLink = Get-SeElement -By XPath -Selection '//*[@id="modal_mountpoint"]/div/div/div[2]/div[1]/a[1]' -Target $SeleniumDriver
            if (!$ContinueWithFacebookLink) {
                throw "Cannot find 'Continue With Facebook' link! Halting!"
                return
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
        #>

        # So we need to check the webpage for an indication that we are actually logged in now
        try {
            $SuccessfulLoginIndicator = Get-SeElement -By XPath -Selection '//*[@href="/userlist/tracking"]' -Target $Driver
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