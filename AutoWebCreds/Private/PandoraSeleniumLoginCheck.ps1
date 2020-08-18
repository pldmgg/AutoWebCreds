$ServiceName = "Pandora"
$SiteUrl = "https://www.pandora.com"

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
    $LoginButton = Get-SeElement -By XPath -Selection '/html/body/div[3]/div/div[2]/div[1]/div/div[2]/div/div[1]/div/ul/li[3]/a' -Target $Driver
    if (!$LoginButton) {
        throw "Unable to find the SignIn button! Halting!"
    }
} catch {
    Write-Error $_
    return
}

if ($LoginButton) {
    try {
        # Have the user provide Credentials
        . .\GetAnyBoxPSCreds.ps1
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

    ### Basic UserName and Password Login ####
    try {
        . .\PandoraUserNamePwdLogin.ps1
        $null = PandoraUserNamePwdLogin -SeleniumDriver $Driver -PSCreds $PSCreds
    } catch {
        Write-Warning $_.Exception.Message
    }

    # So we need to check the webpage for an indication that we are actually logged in now
    try {
        $SuccessfulLoginIndicator = Get-SeElement -By XPath -Selection "//span[contains(text(),'My Collection')]" -Target $Driver
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