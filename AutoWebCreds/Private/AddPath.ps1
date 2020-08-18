function AddPath {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory=$True)]
        [string]$PathToAdd,

        [Parameter(Mandatory=$False)]
        [switch]$UpdateSystemPath
    )

    $DirSep = [System.IO.Path]::DirectorySeparatorChar

    # Update PowerShell $env:Path
    [System.Collections.Arraylist][array]$CurrentEnvPathArray = $env:PATH -split ';' | Where-Object {![System.String]::IsNullOrWhiteSpace($_)} | Sort-Object -Unique
    if ($CurrentEnvPathArray -notcontains $PathToAdd) {
        $CurrentEnvPathArray.Insert(0,$PathToAdd)
        $env:PATH = $CurrentEnvPathArray -join ';'
    }

    if ($UpdateSystemPath) {
        # Update SYSTEM Path
        $null = UpdateSystemPathNow -PathToAdd $PathToAdd
    }
}