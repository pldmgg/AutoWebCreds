$ServiceName = "NPR"
$SiteUrl = "https://www.npr.org/"

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

if (!$(Get-Module -ListAvailable Selenium -ErrorAction SilentlyContinue)) {Install-Module Selenium}
if (!$(Get-Module Selenium -ErrorAction SilentlyContinue)) {Import-Module Selenium}

# Check for chromedriver.exe
if (!$(Get-Command chromedriver.exe -ErrorAction SilentlyContinue)) {
    & .\SeleniumDriverSetup.ps1
}

$ChromeUserData = "$HOME\AppData\Local\Google\Chrome\User Data"
#$ChromeProfile = "Profile 1" # LindaProfile
$ChromeProfile = "Profile 0"

try {
    $Driver = Start-SeChrome -Arguments @("window-size=1200x600", "user-data-dir=$ChromeUserData", "profile-directory=$ChromeProfile")
    # The below Tab + Enter will clear either the "Chrome was not shutdown properly" message or the "Chrome is being controlled by automated software" message
    #[OpenQA.Selenium.Interactions.Actions]::new($Driver).SendKeys([OpenQA.Selenium.Keys]::Tab).Perform()
    #[OpenQA.Selenium.Interactions.Actions]::new($Driver).SendKeys([OpenQA.Selenium.Keys]::Enter).Perform()
    & "C:\Program Files (x86)\EventGhost\EventGhost.exe" -event ClearChromeRestoreMsg
    Enter-SeUrl $SiteUrl -Driver $Driver

    # Determine if we see a "Sign In" button. If we do, then we need to login
    $SignInButton = Get-SeElement -By XPath -Selection '//*[@id="user-account-dropdown-mount"]/div/a' -Target $Driver
    if (!$SignInButton) {
        throw "Unable to find the SignIn button! Halting!"
    }
} catch {
    Write-Error $_
    return
}

if ($SignInButton) {
    # Have the user provide Credentials
    try {
        . .\GetAnyBoxPSCreds.ps1
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
        . .\NPRUserNamePwdLogin.ps1
        $null = NPRUserNamePwdLogin -SeleniumDriver $Driver -PSCreds $PSCreds
    } catch {
        Write-Error $_
        return
    }
    #>

    ### Login With Google ###
    try {
        # Get "Continue with Google" Link
        $LoginWithGoogleButton = Get-SeElement -By XPath -Selection '//*[@id="janrain-googleplus"]' -Target $Driver
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
        . .\GoogleAccountLogin.ps1
        $null = GoogleAccountLogin -SeleniumDriver $Driver -PSCreds $PSCreds
    } catch {
        Write-Warning $_.Exception.Message
    }


    <#
    ### Login With Facebook ###
    try {
        # Get "Continue With Facebook" Link
        $ContinueWithFacebookLink = Get-SeElement -By XPath -Selection '//*[@id="janrain-facebook"]/a' -Target $SeleniumDriver
        if (!$ContinueWithFacebookLink) {
            throw "Cannot find 'Continue With Facebook' link! Halting!"
        }
        Send-SeClick -Element $ContinueWithFacebookLink -Driver $SeleniumDriver
    } catch {
        Write-Error $_
        return
    }

    try {
        . .\FacebookAccountLogin.ps1
        $null = FacebookAccountLogin -SeleniumDriver $Driver -PSCreds $PSCreds
    } catch {
        Write-Warning $_.Exception.Message
    }


    ### Login with Apple ###
    try {
        # Get "Continue With Apple" Link
        $ContinueWithAppleLink = Get-SeElement -By XPath -Selection '//*[@id="janrain-apple"]/a' -Target $SeleniumDriver
        if (!$ContinueWithAppleLink) {
            throw "Cannot find 'Continue With Apple' link! Halting!"
        }
        Send-SeClick -Element $ContinueWithAppleLink -Driver $SeleniumDriver
    } catch {
        Write-Error $_
        return
    }

    try {
        . .\AppleAccountLogin.ps1
        $null = AppleAccountLogin -SeleniumDriver $Driver -PSCreds $PSCreds
    } catch {
        Write-Warning $_.Exception.Message
    }
    #>

    # So we need to check the webpage for an indication that we are actually logged in now
    try {
        $SuccessfulLoginIndicator = Get-SeElement -By XPath -Selection '//*[@id="user-account-dropdown-mount"]/div/a' -Target $Driver
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