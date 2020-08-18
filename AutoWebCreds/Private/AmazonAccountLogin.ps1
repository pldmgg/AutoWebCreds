function AmazonAccountLogin {
    [CmdletBinding()]
    param(
        [parameter(Mandatory=$True)]
        $SeleniumDriver,

        [parameter(Mandatory=$True)]
        [pscredential]$PSCreds
    )

    # Determine if the Authentication window is in the Selenium Parent Window or in a Child PopUp Window
    if (@($SeleniumDriver.WindowHandles).Count -gt 1) {
        try {
            # The Authentication propmpt is in a Child Window that just opened
            $SeleniumDriver.SwitchTo().Window($SeleniumDriver.WindowHandles[-1])
            $ParentWindowHandle = $SeleniumDriver.WindowHandles[0]
        } catch {
            Write-Error $_
            return
        }
    }

    # Get UserName Field
    try {
        $UserNameField = Get-SeElement -By XPath -Selection '//*[@id="ap_email"]' -Target $SeleniumDriver
        if (!$UserNameField) {
            throw "Cannot find UserName/Email field! Halting!"
        }
        Send-SeClick -Element $UserNameField -Driver $SeleniumDriver
    } catch {
        Write-Error $_
        return
    }

    # Enter the user's UserName/Email
    try {
        Send-SeKeys -Element $UserNameField -Keys $PSCreds.UserName -ErrorAction Stop
    }
    catch {
        Write-Error $_
        return
    }

    # Get the Password field
    try {
        $PwdField = Get-SeElement -By XPath -Selection '//*[@id="ap_password"]' -Target $SeleniumDriver
        if (!$PwdField) {
            throw "Cannot find Password field! Halting!"
        }
        Send-SeClick -Element $PwdField -Driver $SeleniumDriver
    } catch {
        Write-Error $_
        return
    }

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
    try {
        $ActuallyLoginButton = Get-SeElement -By XPath -Selection '//*[@id="signInSubmit"]' -Target $SeleniumDriver
        if (!$ActuallyLoginButton) {
            throw "Cannot find the 'Actually Login' button! Halting!"
        }
        Send-SeClick -Element $ActuallyLoginButton -Driver $SeleniumDriver
    } catch {
        Write-Error $_
        return
    }

    if ($ParentWindowHandle) {
        $SeleniumDriver.SwitchTo().Window($ParentWindowHandle)
    }

}