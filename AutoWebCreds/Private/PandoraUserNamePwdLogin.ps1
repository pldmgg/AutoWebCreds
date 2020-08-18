function PandoraUserNamePwdLogin {
    [CmdletBinding()]
    param(
        [parameter(Mandatory=$True)]
        $SeleniumDriver,

        [parameter(Mandatory=$True)]
        [pscredential]$PSCreds
    )

    # Get UserName Field
    $UserNameField = Get-SeElement -By XPath -Selection '/html/body/div[3]/div/main/div/div/div[2]/div[3]/div[1]/div[1]/form/div[1]/div/label/div[2]/input' -Target $SeleniumDriver
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
    $PwdField = Get-SeElement -By XPath -Selection '/html/body/div[3]/div/main/div/div/div[2]/div[3]/div[1]/div[1]/form/div[2]/div/label/div[2]/input' -Target $SeleniumDriver
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
    $ActuallyLoginButton = Get-SeElement -By XPath -Selection '/html/body/div[3]/div/main/div/div/div[2]/div[3]/div[1]/div[1]/form/div[3]/div/button' -Target $SeleniumDriver
    if (!$ActuallyLoginButton) {
        Write-Error "Cannot find the 'Actually Login' button! Halting!"
        return
    }
    Send-SeClick -Element $ActuallyLoginButton -Driver $SeleniumDriver

}