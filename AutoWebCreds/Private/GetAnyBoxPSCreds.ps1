function GetAnyBoxPSCreds {
    [CmdletBinding()]
    param(
        [parameter(Mandatory=$True)]
        $ServiceName
    )

    <#
    # Install/Import the Windows Credential Manager Module
    if (!$(Get-Module CredentialManager -ErrorAction SilentlyContinue)) {
        try {
            Import-Module CredentialManager -UseWindowsPowerShell -ErrorAction Stop
        } catch {
            powershell.exe -NoProfile -NoLogo -NonInteractive -ExecutionPolicy Bypass -Command "Install-Module CredentialManager -Force"
            try {
                Import-Module CredentialManager -UseWindowsPowerShell -ErrorAction Stop
            } catch {
                Write-Error $_
                return
            }
        }
    }
    # Add AnyBox Module for input window popup in GUI
    if (!$(Get-Module AnyBox -ErrorAction SilentlyContinue)) {
        try {
            Import-Module AnyBox -UseWindowsPowerShell -ErrorAction Stop
        } catch {
            powershell.exe -NoProfile -NoLogo -NonInteractive -ExecutionPolicy Bypass -Command "Install-Module AnyBox -Force"
            try {
                Import-Module AnyBox -UseWindowsPowerShell -ErrorAction Stop
            } catch {
                Write-Error $_
                return
            }
        }
    }
    #>

    # See if we can get the user's $ServiceName Credentials from the Windows Credential Manager
    try {
        $StoredCreds = Get-StoredCredential -Target $ServiceName -ErrorAction Stop
        if (!$StoredCreds) {throw "Unable to find Windows Credential Manager Target called '$ServiceName'"}
    } catch {
        $CmdString = @"
if (!`$(Get-Module -ListAvailable AnyBox -ErrorAction SilentlyContinue)) {Install-Module AnyBox}
if (!`$(Get-Module AnyBox -ErrorAction SilentlyContinue)) {Import-Module AnyBox}

`$InputResult = Show-AnyBox -Title '$ServiceName Credentials' -Buttons 'Cancel','Submit' -MinWidth 400 -FontSize 20 -Prompts @(
New-AnyBoxPrompt -Message 'UserName:'
New-AnyBoxPrompt -Message 'Password:' -InputType Password
)

'[PSCustomObject]@{UserName = ' + "'" + `$InputResult.Input_0 + "'" + '; ' + 'Password = ' + "'" + [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR(`$InputResult.Input_1)) + "'" + '}'
"@
        try {
            $EncodedCmd = [System.Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($CmdString))
            $InvokeCmdString = powershell.exe -NoProfile -NoLogo -ExecutionPolicy Bypass -EncodedCommand $EncodedCmd
            $CredentialsPSObj = Invoke-Expression $InvokeCmdString
        } catch {
            Write-Error $_
            return
        }

        $CredManObj = New-StoredCredential -Target $ServiceName -Username $CredentialsPSObj.UserName -Password $CredentialsPSObj.Password
        $StoredCreds = Get-StoredCredential -Target $ServiceName -ErrorAction Stop
    }

    $StoredCreds

}