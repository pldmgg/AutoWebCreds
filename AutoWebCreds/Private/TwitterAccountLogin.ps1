function TwitterAccountLogin {
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

    # Next, click the Email field
    try {
        $EmailField = Get-SeElement -By XPath -Selection '//*[@id="username_or_email"]' -Target $SeleniumDriver
        if (!$EmailField) {
            throw "Cannot find Google's Email field! Halting!"
        }
        Send-SeClick -Element $EmailField -Driver $SeleniumDriver
    } catch {
        Write-Error $_
        return
    }

    # Enter the user's email address
    try {
        Send-SeKeys -Element $EmailField -Keys $PSCreds.UserName -ErrorAction Stop
    }
    catch {
        Write-Error $_
        return
    }

    # Get the password field
    try {
        $PwdField = Get-SeElement -By XPath -Selection '//*[@id="password"]' -Target $SeleniumDriver
        if (!$PwdField) {
            throw "Cannot find Google Password field! Halting!"
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

    # Click the "Authorize" button to complete Login
    try {
        $AuthorizeButton = Get-SeElement -By XPath -Selection '//*[@id="allow"]' -Target $SeleniumDriver
        if (!$AuthorizeButton) {
            throw "Cannot find the Twitter 'Authorize' button! Halting!"
        }
        Send-SeClick -Element $AuthorizeButton -Driver $SeleniumDriver
    } catch {
        Write-Error $_
        return
    }

    if ($ParentWindowHandle) {
        $SeleniumDriver.SwitchTo().Window($ParentWindowHandle)
    }
}