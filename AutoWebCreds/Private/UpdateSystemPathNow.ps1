function UpdateSystemPathNow {
    [CmdletBinding()]
    param(
        [parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$PathToAdd
    )

    $RegistrySystemPath = 'HKLM:\System\CurrentControlSet\Control\Session Manager\Environment'
    $CurrentSystemPath = $(Get-ItemProperty -Path $RegistrySystemPath -Name PATH).Path
    [System.Collections.Arraylist][array]$CurrentSystemPathArray = $CurrentSystemPath -split ';' | Where-Object {![System.String]::IsNullOrWhiteSpace($_)} | Sort-Object -Unique

    if ($CurrentSystemPathArray -notcontains $PathToAdd) {
        $CurrentSystemPathArray.Insert(0,$PathToAdd)
        $UpdatedSystemPath = $CurrentSystemPathArray -join ';'
        Set-ItemProperty -Path $RegistrySystemPath -Name PATH -Value $UpdatedSystemPath

        # Now the registry is updated, but current processes haven't taken the changes.
        # We will now force all open processes/windows to take the updated system PATH

        if (-not $("Win32.NativeMethods" -as [Type])) {
            # import sendmessagetimeout from win32
            $null = Add-Type -Namespace Win32 -Name NativeMethods -MemberDefinition @"
[DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
public static extern IntPtr SendMessageTimeout(
IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam,
uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);
"@
        }

        $HWND_BROADCAST = [IntPtr] 0xffff
        $WM_SETTINGCHANGE = 0x1a
        $result = [UIntPtr]::Zero

        # notify all windows of environment block change
        [Win32.Nativemethods]::SendMessageTimeout($HWND_BROADCAST, $WM_SETTINGCHANGE, [UIntPtr]::Zero, "Environment", 2, 5000, [ref] $result)
    }
}