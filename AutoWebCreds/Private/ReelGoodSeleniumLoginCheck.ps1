function ReelGoodSeleniumLoginCheck {
    [CmdletBinding()]
    param(
        [parameter(Mandatory=$false)]
        [ValidatePattern('[0-9]')]
        [int]$ChromeProfileNumber = '0'
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
        $null = CheckUrlStatus -SiteUrl $SiteUrl
    } catch {
        Write-Error $_
        return
    }

    try {
        $null = ChromeDriverAndEventGhostCheck -ErrorAction Stop
    } catch {
        Write-Error $_
        return
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
        #& "C:\Program Files (x86)\EventGhost\EventGhost.exe" -event ClearChromeRestoreMsg
        $EventGhostProcess = Get-Process eventghost -ErrorAction SilentlyContinue
        if ($EventGhostProcess) {$null = $EventGhostProcess | Stop-Process -ErrorAction SilentlyContinue}
        $EventGhostConfigFilePath = $(Get-Module AutoWebCreds).ModuleBase + '\' + 'EventGhost' + '\' + 'ConfigurationFiles' + '\' + 'eventghosttreett.xml'
        $null = Start-Process -FilePath "C:\Program Files (x86)\EventGhost\EventGhost.exe" -ArgumentList "-file `"$EventGhostConfigFilePath`""
        Start-Sleep -Seconds 1
        $null = Start-Process -FilePath "C:\Program Files (x86)\EventGhost\EventGhost.exe" -ArgumentList "-event `"MinimizeEventGhost`""
        Start-Sleep -Seconds 1
        $null = Start-Process -FilePath "C:\Program Files (x86)\EventGhost\EventGhost.exe" -ArgumentList "-event `"ClearChromeRestoreMsg`""
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
        if ([System.Environment]::OSVersion.Version.Build -lt 10240) {
            try {
                # Have the user provide Credentials
                [pscredential]$PSCreds = GetAnyBoxPSCreds -ServiceName $ServiceName
            } catch {
                Write-Error $_
                return
            }
        } else {
            try {
                [pscredential]$PSCreds = UWPCredPrompt -ServiceName $ServiceName -SiteUrl $SiteUrl
            } catch {
                Write-Error $_
                return
            }
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
                throw 'Unable to determine login was successful!'
            }
        } catch {
            Write-Warning $_.Exception.Message
        }
    }

    $Driver

    <#
    $Driver.Close()
    $Driver.Dispose()
    #>
}

# SIG # Begin signature block
# MIIMaAYJKoZIhvcNAQcCoIIMWTCCDFUCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUz+el/M907ZuI/3yzGvGeK5Bt
# 9EegggndMIIEJjCCAw6gAwIBAgITawAAAERR8umMlu6FZAAAAAAARDANBgkqhkiG
# 9w0BAQsFADAwMQwwCgYDVQQGEwNMQUIxDTALBgNVBAoTBFpFUk8xETAPBgNVBAMT
# CFplcm9EQzAxMB4XDTE5MTEyODEyMjgyNloXDTIxMTEyODEyMzgyNlowPTETMBEG
# CgmSJomT8ixkARkWA0xBQjEUMBIGCgmSJomT8ixkARkWBFpFUk8xEDAOBgNVBAMT
# B1plcm9TQ0EwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQC0crvKbqlk
# 77HGtaVMWpZBOKwb9eSHzZjh5JcfMJ33A9ORwelTAzpRP+N0k/rAoQkauh3qdeQI
# fsqdcrEiingjiOvxaX3lHA5+fVGe/gAnZ+Cc7iPKXJVhw8jysCCld5zIG8x8eHuV
# Z540iNXdI+g2mustl+l5q4kcWukj+iQwtCYEaCgAXB9qlkT33sX0k/07JoSYcGJx
# ++0SHnF0HBw7Gs/lHlyt4biIGtJleOw0iIN2yVD9UrVWMtKrghKPaW31mjYYeN5k
# ckYzBit/Kokxo0m54B4M3aLRPBQdXH1wL6A894BAlUlPM7vrozU2cLrZgcFuEvwM
# 0cLN8mfGKbo5AgMBAAGjggEqMIIBJjASBgkrBgEEAYI3FQEEBQIDAgADMCMGCSsG
# AQQBgjcVAgQWBBQIf0JBlAvGtUeDPLbljq9G8OOkkzAdBgNVHQ4EFgQUkNLPVlgd
# vV0pNGjQxY8gU/mxzMIwGQYJKwYBBAGCNxQCBAweCgBTAHUAYgBDAEEwDgYDVR0P
# AQH/BAQDAgGGMA8GA1UdEwEB/wQFMAMBAf8wHwYDVR0jBBgwFoAUdpW6phL2RQNF
# 7AZBgQV4tgr7OE0wMQYDVR0fBCowKDAmoCSgIoYgaHR0cDovL3BraS9jZXJ0ZGF0
# YS9aZXJvREMwMS5jcmwwPAYIKwYBBQUHAQEEMDAuMCwGCCsGAQUFBzAChiBodHRw
# Oi8vcGtpL2NlcnRkYXRhL1plcm9EQzAxLmNydDANBgkqhkiG9w0BAQsFAAOCAQEA
# WObmEzp48rKuXiJ628N7F/clqVVG+dl6UNCrPGK/fr+TbEE3RFpsPfd166gTFF65
# 5ZEbas8qW11makxfIL41GykCZSHMCJBhFhh68xnBSsplemm2CAb06+j2dkuvmOR3
# Aa9+ujtW8eSgNcSr3dkYa3fZfV3siTaY+9FmEWH8D0tglEUuUv1+KPAwXRvdNN7f
# pAsyL5qq/canjqR6/BmLSXdoD3LPISDH/iZpboBwCrhy+imupusnxjZdYFP/Siox
# g7dbvcSkr05t6jlr8xABrU+zzK3yUol/WHOnE70krG3JONBO3kN+Jv/hktIt5pd6
# imtXSPImm4BUPGa7ppeVNDCCBa8wggSXoAMCAQICE1gAAAJQw22Yn6op/pMAAwAA
# AlAwDQYJKoZIhvcNAQELBQAwPTETMBEGCgmSJomT8ixkARkWA0xBQjEUMBIGCgmS
# JomT8ixkARkWBFpFUk8xEDAOBgNVBAMTB1plcm9TQ0EwHhcNMTkxMTI4MTI1MDM2
# WhcNMjExMTI3MTI1MDM2WjBJMUcwRQYDVQQDEz5aZXJvQ29kZTEzLE9VPURldk9w
# cyxPPVRlY2ggVGFyZ2V0cywgTExDLEw9QnJ5biBNYXdyLFM9UEEsQz1VUzCCASIw
# DQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAPYULq1HCD/SgqTajXuWjnzVedBE
# Nc3LQwdDFmOLyrVPi9S9FF3yYDCTywA6wwgxSQGhI8MVWwF2Xdm+e6pLX+957Usk
# /lZGHCNwOMP//vodJUhxcyDZG7sgjjz+3qBl0OhUodZfqlprcVMQERxlIK4djDoP
# HhIBHBm6MZyC9oiExqytXDqbns4B1MHMMHJbCBT7KZpouonHBK4p5ObANhGL6oh5
# GnUzZ+jOTSK4DdtulWsvFTBpfz+JVw/e3IHKqHnUD4tA2CxxA8ofW2g+TkV+/lPE
# 9IryeA6PrAy/otg0MfVPC2FKaHzkaaMocnEBy5ZutpLncwbwqA3NzerGmiMCAwEA
# AaOCApowggKWMA4GA1UdDwEB/wQEAwIHgDAdBgNVHQ4EFgQUW0DvcuEW1X6BD+eQ
# 2AJHO2eur9UwHwYDVR0jBBgwFoAUkNLPVlgdvV0pNGjQxY8gU/mxzMIwgekGA1Ud
# HwSB4TCB3jCB26CB2KCB1YaBrmxkYXA6Ly8vQ049WmVyb1NDQSgyKSxDTj1aZXJv
# U0NBLENOPUNEUCxDTj1QdWJsaWMlMjBLZXklMjBTZXJ2aWNlcyxDTj1TZXJ2aWNl
# cyxDTj1Db25maWd1cmF0aW9uLERDPXplcm8sREM9bGFiP2NlcnRpZmljYXRlUmV2
# b2NhdGlvbkxpc3Q/YmFzZT9vYmplY3RDbGFzcz1jUkxEaXN0cmlidXRpb25Qb2lu
# dIYiaHR0cDovL3BraS9jZXJ0ZGF0YS9aZXJvU0NBKDIpLmNybDCB5gYIKwYBBQUH
# AQEEgdkwgdYwgaMGCCsGAQUFBzAChoGWbGRhcDovLy9DTj1aZXJvU0NBLENOPUFJ
# QSxDTj1QdWJsaWMlMjBLZXklMjBTZXJ2aWNlcyxDTj1TZXJ2aWNlcyxDTj1Db25m
# aWd1cmF0aW9uLERDPXplcm8sREM9bGFiP2NBQ2VydGlmaWNhdGU/YmFzZT9vYmpl
# Y3RDbGFzcz1jZXJ0aWZpY2F0aW9uQXV0aG9yaXR5MC4GCCsGAQUFBzAChiJodHRw
# Oi8vcGtpL2NlcnRkYXRhL1plcm9TQ0EoMykuY3J0MD0GCSsGAQQBgjcVBwQwMC4G
# JisGAQQBgjcVCIO49D+Em/J5g/GPOIOwtzKG0c14gSeh88wfj9lVAgFkAgEFMBMG
# A1UdJQQMMAoGCCsGAQUFBwMDMBsGCSsGAQQBgjcVCgQOMAwwCgYIKwYBBQUHAwMw
# DQYJKoZIhvcNAQELBQADggEBAEfjH/emq+TnlhFss6cNor/VYKPoEeqYgFwzGbul
# dzPdPEBFUNxcreN0b61kxfenAHifvI0LCr/jDa8zGPEOvo8+zB/GWp1Huw/xLMB8
# rfZHBCox3Av0ohjzO5Ac5yCHijZmrwaXV3XKpBncWdC6pfr/O0bIoRMbvV9EWkYG
# fpNaFvR8piUGJ47cLlC+NFTOQcmESOmlsy+v8JeG9OPsnvZLsD6sydajrxRnNlSm
# zbK64OrbSM9gQoA6bjuZ6lJWECCX1fEYDBeZaFrtMB/RTVQLF/btisfDQXgZJ+Tw
# Tjy+YP39D0fwWRfAPSRJ8NcnRw4Ccj3ngHz7e0wR6niCtsMxggH1MIIB8QIBATBU
# MD0xEzARBgoJkiaJk/IsZAEZFgNMQUIxFDASBgoJkiaJk/IsZAEZFgRaRVJPMRAw
# DgYDVQQDEwdaZXJvU0NBAhNYAAACUMNtmJ+qKf6TAAMAAAJQMAkGBSsOAwIaBQCg
# eDAYBgorBgEEAYI3AgEMMQowCKACgAChAoAAMBkGCSqGSIb3DQEJAzEMBgorBgEE
# AYI3AgEEMBwGCisGAQQBgjcCAQsxDjAMBgorBgEEAYI3AgEVMCMGCSqGSIb3DQEJ
# BDEWBBTBU7qXP/d1yF1s7MpoMZ7uS1/UIjANBgkqhkiG9w0BAQEFAASCAQC30ArK
# r01rIjaXfw8gVAzJ+LLANLyRKhZsuiY9YalZtb4yz8WWP4cvvPPdtpYp3DgrxVoX
# 75O+5K1WGjL9Z4G8NlI2Bc/BY1h4klC7oqVbGW7vXOn/SulsaCK8YG93zqYTjvBW
# t3AsjAh6/ogiKDcj5QCWMzut+aKLDjF0Z/eZKPOr7EN1TqHXcbhYrq2USCc0bZmz
# y6GFOwB+X4TSMQxoqGJPKFfNZi4r42GIdihUvZyGAYHuXkR31caAlKarY3P6VEXC
# jpFdwVSaCG2dZ+Qx7MBCx+JAufo76qwPsGVCtAB2NtBKFhzX8yaA9VgalwSpHjah
# 27vL3aE0njJ+T9i7
# SIG # End signature block
