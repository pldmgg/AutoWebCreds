function UWPCredPrompt {
    [CmdletBinding()]
    param(
        [parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [ValidateSet("AmazonMusic","Audible","GooglePlay","InternetArchive","NPR","Pandora","ReelGood","Spotify","Tidal","TuneIn","YouTube","YouTubeMusic")]
        [string]$ServiceName,

        [parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$SiteUrl
    )

    # Reference: https://www.meziantou.net/how-to-prompt-for-a-password-on-windows.htm

    #region >> Helper Functions

    function Await($WinRtTask, $ResultType) {
        $asTask = $asTaskGeneric.MakeGenericMethod($ResultType)
        $netTask = $asTask.Invoke($null, @($WinRtTask))
        $netTask.Wait(-1) | Out-Null
        $netTask.Result
    }

    function AwaitAction($WinRtAction) {
        $asTask = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and !$_.IsGenericMethod })[0]
        $netTask = $asTask.Invoke($null, @($WinRtAction))
        $netTask.Wait(-1) | Out-Null
    }

    #endregion >> Helper Functions

    # See if we can get the user's $ServiceName Credentials from the Windows Credential Manager
    try {
        $StoredCreds = Get-StoredCredential -Target $ServiceName -ErrorAction Stop
        if (!$StoredCreds) {throw "Unable to find Windows Credential Manager Target called '$ServiceName'"}
    } catch {
        # The below will make all of the other Windows.Security.Credentials.UI classes available
        $null = [Windows.Security.Credentials.UI.CredentialPicker,Windows.Security.Credentials,ContentType=WindowsRuntime]

        # The below will make all of the other Windows.UI.Popups classes available
        $null = [Windows.UI.Popups.MessageDialog,Windows.UI.Popups,ContentType=WindowsRuntime]

        # The below will make all of the other Windows.UI.Popups classes available
        $null = [Windows.UI.Xaml.AdaptiveTrigger,Windows.UI.Xaml,ContentType=WindowsRuntime]

        # The below will make all of the other Windows.UI.Xaml.Controls classes available
        $null = [Windows.UI.Xaml.Controls.AppBar,Windows.UI.Xaml.Controls,ContentType=WindowsRuntime]

        # Reference: https://superuser.com/questions/1341997/using-a-uwp-api-namespace-in-powershell
        $null = Add-Type -AssemblyName System.Runtime.WindowsRuntime
        $asTaskGeneric = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]

        $Options = [Windows.Security.Credentials.UI.CredentialPickerOptions]::new()
        $Options.TargetName = $SiteUrl
        $Options.Caption = $SiteUrl
        $Options.Message = "This will allow authentication to $ServiceName"
        $Options.CredentialSaveOption = [Windows.Security.Credentials.UI.CredentialSaveOption]::Unselected
        $Options.AuthenticationProtocol = [Windows.Security.Credentials.UI.AuthenticationProtocol]::Basic

        $CredentialPickerResults = Await $([Windows.Security.Credentials.UI.CredentialPicker]::PickAsync($Options)) ([Windows.Security.Credentials.UI.CredentialPickerResults])

        $UserName = $CredentialPickerResults.CredentialUserName
        #$PwdSS = ConvertTo-SecureString $CredentialPickerResults.CredentialPassword -AsPlainText -Force

        #$CredManObj = New-StoredCredential -Target $ServiceName -Username $UserName -Password $CredentialPickerResults.CredentialPassword
        $ArgList = "-NoProfile -NoLogo -NonInteractive -ExecutionPolicy Bypass -Command `"New-StoredCredential -Target $ServiceName -UserName $UserName -Password $($CredentialPickerResults.CredentialPassword)`""
        $null = Start-Process -FilePath powershell.exe -NoNewWindow -Wait -ArgumentList $ArgList
        $StoredCreds = Get-StoredCredential -Target $ServiceName -ErrorAction Stop
    }

    # Output
    $StoredCreds

    #$MsgDialog = [Windows.UI.Popups.MessageDialog]::new($("User: {0}, Password: {1}, Domain: {2}" -f $CredentialPickerResults.CredentialUserName, $CredentialPickerResults.CredentialPassword, $CredentialPickerResults.CredentialDomainName))
    #$MsgDialog.ShowAsync()
}
