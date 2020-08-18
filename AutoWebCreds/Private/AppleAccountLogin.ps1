function AppleAccountLogin {
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

    # Next, click the Apple Login screen Email field
    try {
        $EmailField = Get-SeElement -By XPath -Selection '//*[@id="account_name_text_field"]' -Target $SeleniumDriver
        if (!$EmailField) {
            throw "Cannot find Email field! Halting!"
        }
        Send-SeClick -Element $EmailField -Driver $SeleniumDriver
    } catch {
        Write-Error $_
        return
    }

    # Enter the user's email address
    #[OpenQA.Selenium.Interactions.Actions]::new($SeleniumDriver).SendKeys('ldimaggiott@gmail.com').Perform()
    try {
        Send-SeKeys -Element $EmailField -Keys $PSCreds.UserName -ErrorAction Stop
    }
    catch {
        Write-Error $_
        return
    }

    # Click the Right-Arrow button
    try {
        $NextButton = Get-SeElement -By XPath -Selection '//*[@id="sign-in"]' -Target $SeleniumDriver
        if (!$NextButton) {
            throw "Cannot find 'Right-Arrow' button! Halting!"
        }
        Send-SeClick -Element $NextButton -Driver $SeleniumDriver
    } catch {
        Write-Error $_
        return
    }

    # Get the Apple Password field
    try {
        $PwdField = Get-SeElement -By XPath -Selection '//*[@id="password_text_field"]' -Target $SeleniumDriver
        if (!$PwdField) {
            throw "Cannot find Apple Password field! Halting!"
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

    # Click the "Next" button to complete Login
    try {
        $PwdNextButton = Get-SeElement -By XPath -Selection '//*[@id="sign-in"]' -Target $SeleniumDriver
        if (!$PwdNextButton) {
            throw "Cannot find 'Right-Arrow' button! Halting!"
        }
        Send-SeClick -Element $PwdNextButton -Driver $SeleniumDriver
    } catch {
        Write-Error $_
        return
    }

    if ($ParentWindowHandle) {
        $SeleniumDriver.SwitchTo().Window($ParentWindowHandle)
    }
}