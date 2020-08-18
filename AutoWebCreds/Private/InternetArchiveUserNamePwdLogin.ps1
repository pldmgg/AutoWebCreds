function InternetArchiveUserNamePwdLogin {
    [CmdletBinding()]
    param(
        [parameter(Mandatory=$True)]
        $SeleniumDriver,

        [parameter(Mandatory=$True)]
        [pscredential]$PSCreds
    )

    # Get UserName Field
    $UserNameField = Get-SeElement -By XPath -Selection '//*[@id="maincontent"]/div/div/div[2]/section[2]/form/label[1]/input' -Target $SeleniumDriver
    if (!$UserNameField) {
        Write-Error "Cannot find UserName/Email field! Halting!"
        return
    }
    Send-SeClick -Element $UserNameField -Driver $SeleniumDriver

    # Enter the user's UserName/Email
    try {
        Send-SeKeys -Element $UserNameField -Keys $PSCreds.UserName -ErrorAction Stop
    }
    catch {
        Write-Error $_
        return
    }

    # Get the Password field
    $PwdField = Get-SeElement -By XPath -Selection '//*[@id="maincontent"]/div/div/div[2]/section[2]/form/label[2]/div/input' -Target $SeleniumDriver
    if (!$PwdField) {
        Write-Error "Cannot find Password field! Halting!"
        return
    }
    Send-SeClick -Element $PwdField -Driver $SeleniumDriver

    # Enter the user's password
    try {
        $PwdPT = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($PSCreds.Password))
        Send-SeKeys -Element $PwdField -Keys $PwdPT -ErrorAction Stop
    }
    catch {
        Write-Error $_
        return
    }

    # Click the "Login" button to complete Login
    $ActuallyLoginButton = Get-SeElement -By XPath -Selection '//*[@id="maincontent"]/div/div/div[2]/section[2]/form/input[3]' -Target $SeleniumDriver
    if (!$ActuallyLoginButton) {
        Write-Error "Cannot find the 'Actually Login' button! Halting!"
        return
    }
    Send-SeClick -Element $ActuallyLoginButton -Driver $SeleniumDriver

}