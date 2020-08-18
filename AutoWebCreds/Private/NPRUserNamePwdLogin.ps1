function NPRUserNamePwdLogin {
    [CmdletBinding()]
    param(
        [parameter(Mandatory=$True)]
        $SeleniumDriver,

        [parameter(Mandatory=$True)]
        [pscredential]$PSCreds
    )

    # Get UserName Field
    $UserNameField = Get-SeElement -By XPath -Selection '//*[@id="email"]' -Target $SeleniumDriver
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

    # Click the "Next" button to reveal Password field
    $NextButton = Get-SeElement -By XPath -Selection '//*[@id="login-form-container"]/form/button' -Target $SeleniumDriver
    if (!$NextButton) {
        Write-Error "Cannot find the 'Next' button! Halting!"
        return
    }
    Send-SeClick -Element $NextButton -Driver $SeleniumDriver

    # Get the Password field
    $PwdField = Get-SeElement -By XPath -Selection '//*[@id="password"]' -Target $SeleniumDriver
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

    # Click the "Next" button to complete Login
    $SignInButton = Get-SeElement -By XPath -Selection '//*[@id="login-submit"]' -Target $SeleniumDriver
    if (!$SignInButton) {
        Write-Error "Cannot find the 'Actually Login' button! Halting!"
        return
    }
    Send-SeClick -Element $SignInButton -Driver $SeleniumDriver

}