[CmdletBinding(DefaultParameterSetName = 'task')]
Param (
    [Parameter(
        Mandatory = $False,
        ParameterSetName = 'task',
        Position = 0
    )]
    [string[]]$Task = 'Default',

    [Parameter(Mandatory = $False)]
    [string]$CertFileForSignature,

    [Parameter(Mandatory = $False)]
    [ValidateNotNullorEmpty()]
    [System.Security.Cryptography.X509Certificates.X509Certificate2]$Cert,

    [Parameter(Mandatory = $False)]
    [pscredential]$AdminUserCreds,

    [Parameter(
        Mandatory = $False,
        ParameterSetName = 'help'
    )]
    [switch]$Help,

    [Parameter(Mandatory = $False)]
    [switch]$AppVeyorContext
)

# Workflow is build.ps1 -> psake.ps1 -> *Tests.ps1

##### BEGIN Prepare For Build #####

$ElevationCheck = [System.Security.Principal.WindowsPrincipal]::new([System.Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
if (!$ElevationCheck) {
    Write-Error "You must run the build.ps1 as an Administrator (i.e. elevated PowerShell Session)! Halting!"
    $global:FunctionResult = "1"
    return
}

if ($AdminUserCreds) {
    # Make sure $AdminUserCreds.UserName format is <Domain>\<User> and <LocalHostName>\<User>
    if ($AdminUserCreds.UserName -notmatch "[\w]+\\[\w]+") {
        Write-Error "The UserName provided in the PSCredential -AdminUserCreds is not in the correct format! Please create the PSCredential with a UserName in the format <Domain>\<User> or <LocalHostName>\<User>. Halting!"
        $global:FunctionResult = "1"
        return
    }
}

if (!$(Get-Module -ListAvailable PSDepend)) {
    & $(Resolve-Path "$PSScriptRoot\*Help*\Install-PSDepend.ps1").Path
}
try {
    Import-Module PSDepend
    $null = Invoke-PSDepend -Path "$PSScriptRoot\build.requirements.psd1" -Install -Import -Force

    # Hack to fix AppVeyor Error When attempting to Publish to PSGallery
    # The specific error this fixes is a problem with the Publish-Module cmdlet from PowerShellGet. PSDeploy
    # calls Publish-Module without the -Force parameter which results in this error: https://github.com/PowerShell/PowerShellGet/issues/79
    # This is more a problem with PowerShellGet than PSDeploy.
    <#
    Remove-Module PSDeploy
    $PSDeployScriptToEdit = Get-Childitem -Path $(Get-Module -ListAvailable PSDeploy).ModuleBase -File -Recurse -Filter "PSGalleryModule.ps1"
    [System.Collections.ArrayList][array]$PSDeployScriptContent = Get-Content $PSDeployScriptToEdit.FullName
    $LineOfInterest = $($PSDeployScriptContent | Select-String -Pattern ".*?Verbose[\s]+= \`$VerbosePreference").Matches.Value
    $IndexOfLineOfInterest = $PSDeployScriptContent.IndexOf($LineOfInterest)
    $PSDeployScriptContent.Insert($($IndexOfLineOfInterest+1),"            Force      = `$True")
    Set-Content -Path $PSDeployScriptToEdit.FullName -Value $PSDeployScriptContent
    #>
    Import-Module PSDeploy
}
catch {
    Write-Error $_
    $global:FunctionResult = "1"
    return
}

Set-BuildEnvironment -Force -Path $PSScriptRoot -ErrorAction SilentlyContinue

# Now the following Environment Variables with similar values should be available to use...
<#
    $env:BHBuildSystem = "Unknown"
    $env:BHProjectPath = "U:\powershell\ProjectRepos\Sudo"
    $env:BHBranchName = "master"
    $env:BHCommitMessage = "!deploy"
    $env:BHBuildNumber = 0
    $env:BHProjectName = "Sudo"
    $env:BHPSModuleManifest = "U:\powershell\ProjectRepos\Sudo\Sudo\Sudo.psd1"
    $env:BHModulePath = "U:\powershell\ProjectRepos\Sudo\Sudo"
    $env:BHBuildOutput = "U:\powershell\ProjectRepos\Sudo\BuildOutput"

    Write-Host "`$env:BHBuildSystem is $env:BHBuildSystem"
    Write-Host "`$env:BHProjectPath is $env:BHProjectPath"
    Write-Host "`$env:BHBranchName is $env:BHBranchName"
    Write-Host "`$env:BHCommitMessage is $env:BHCommitMessage"
    Write-Host "`$env:BHBuildNumber is $env:BHBuildNumber"
    Write-Host "`$env:BHProjectName is $env:BHProjectName"
    Write-Host "`$env:BHPSModuleManifest is $env:BHPSModuleManifest"
    Write-Host "`$env:BHModulePath is $env:BHModulePath"
    Write-Host "`$env:BHBuildOutput is $env:BHBuildOutput"
#>

# Make sure everything is valid PowerShell before continuing...
$FilesToAnalyze = Get-ChildItem $PSScriptRoot -Recurse -File | Where-Object {
    $_.Extension -match '\.ps1|\.psm1|\.psd1'
}
[System.Collections.ArrayList]$InvalidPowerShell = @()
foreach ($FileItem in $FilesToAnalyze) {
    $contents = Get-Content -Path $FileItem.FullName -ErrorAction Stop
    $errors = $null
    $null = [System.Management.Automation.PSParser]::Tokenize($contents, [ref]$errors)
    if ($errors.Count -gt 0 -and $FileItem.Name -ne "$env:BHProjectName.psm1") {
        $null = $InvalidPowerShell.Add($FileItem)
    }
}
if ($InvalidPowerShell.Count -gt 0) {
    Write-Error "The following files are not valid PowerShell:`n$($InvalidPowerShell.FullName -join "`n")`nHalting!"
    $global:FunctionResult = "1"
    return
}

#region >> Sign Everything

if ($CertFileForSignature -and !$Cert) {
    if (!$(Test-Path $CertFileForSignature)) {
        Write-Error "Unable to find the Certificate specified to be used for Code Signing! Halting!"
        $global:FunctionResult = "1"
        return
    }

    try {
        $Cert = Get-PfxCertificate $CertFileForSignature -ErrorAction Stop
        if (!$Cert) {throw "There was a prblem with the Get-PfcCertificate cmdlet! Halting!"}
    }
    catch {
        Write-Error $_
        $global:FunctionResult = "1"
        return
    }
}

if ($Cert) {
    # Make sure the Cert is good for Code Signing
    if ($Cert.EnhancedKeyUsageList.ObjectId -notcontains "1.3.6.1.5.5.7.3.3") {
        $CNOfCert = $($($Cert.Subject -split ",")[0] -replace "CN=","").Trim()
        Write-Error "The provided Certificate $CNOfCert says that it should be sued for $($Cert.EnhancedKeyUsageList.FriendlyName -join ','), NOT 'Code Signing'! Halting!"
        $global:FunctionResult = "1"
        return
    }

    # Make sure our ProtoHelpers are signed before we do anything else, otherwise we won't be able to use them
    $HelperFilestoSign = Get-ChildItem $(Resolve-Path "$PSScriptRoot\*Help*\").Path -Recurse -File | Where-Object {
        $_.Extension -match '\.ps1|\.psm1|\.psd1|\.ps1xml' -and $_.Name -ne "Remove-Signature.ps1"
    }

    # Before we loop through and sign the Helper functions, we need to sign Remove-Signature.ps1
    $RemoveSignatureFilePath = $(Resolve-Path "$PSScriptRoot\*Help*\Remove-Signature.ps1").Path
    if (!$(Test-Path $RemoveSignatureFilePath)) {
        Write-Error "Unable to find the path $RemoveSignatureFilePath! Halting!"
        $global:FunctionResult = "1"
        return
    }

    # Because Set-Authenticode sometimes eats a trailing line when it is used, make sure Remove-Signature.ps1 doesn't break
    $SingatureLineRegex = '^# SIG # Begin signature block|^<!-- SIG # Begin signature block -->'
    $RemoveSignatureContent = Get-Content $RemoveSignatureFilePath
    [System.Collections.ArrayList]$UpdatedRemoveSignatureContent = @()
    foreach ($line in $RemoveSignatureContent) {
        if ($line -match $SingatureLineRegex) {
            $null = $UpdatedRemoveSignatureContent.Add("`n")
            break
        }
        else {
            $null = $UpdatedRemoveSignatureContent.Add($line)
        }
    }
    Set-Content -Path $RemoveSignatureFilePath -Value $UpdatedRemoveSignatureContent

    try {
        $SetAuthenticodeResult = Set-AuthenticodeSignature -FilePath $RemoveSignatureFilePath -Cert $Cert
        if (!$SetAuthenticodeResult -or $SetAuthenticodeResult.Status -ne "Valid") {throw "There was a problem using the Set-AuthenticodeSignature cmdlet to sign the Remove-Signature.ps1 function! Halting!"}
    }
    catch {
        Write-Error $_
        $global:FunctionResult = "1"
        return
    }

    # Dot Source the Remove-Signature function
    . $RemoveSignatureFilePath
    if (![bool]$(Get-Item Function:\Remove-Signature)) {
        Write-Error "Problem dot sourcing the Remove-Signature function! Halting!"
        $global:FunctionResult = "1"
        return
    }

    # Loop through the Help Scripts/Functions and sign them so that we can use them immediately if necessary
    Remove-Signature -FilePath $HelperFilestoSign.FullName

    [System.Collections.ArrayList]$FilesFailedToSign = @()
    foreach ($FilePath in $HelperFilestoSign.FullName) {
        try {
            Write-Host "Signing $FilePath..."
            $SetAuthenticodeResult = Set-AuthenticodeSignature -FilePath $FilePath -cert $Cert
            if (!$SetAuthenticodeResult -or $SetAuthenticodeResult.Status -ne "Valid") {throw}
        }
        catch {
            Write-Warning "Signing $FilePath failed!"
            $null = $FilesFailedToSign.Add($FilePath)
        }
    }

    if ($FilesFailedToSign.Count -gt 0) {
        Write-Error "Halting because we failed to digitally sign the following files:`n$($FilesFailedToSign -join "`n")"
        $global:FunctionResult = "1"
        return
    }
}

if ($Cert) {
    # NOTE: We don't want to include the Module's .psm1 or .psd1 yet because the psake.ps1 Compile Task hasn't finalized them yet...
    # NOTE: We don't want to sign build.ps1, Remove-Signature.ps1, or Helper functions because we just did that above...
    $HelperFilesToSignNameRegex = $HelperFilestoSign.Name | foreach {[regex]::Escape($_)}
    $RemoveSignatureFilePathRegex = [regex]::Escape($RemoveSignatureFilePath)
    [System.Collections.ArrayList][array]$FilesToSign = Get-ChildItem $env:BHProjectPath -Recurse -File | Where-Object {
        $_.Extension -match '\.ps1|\.psm1|\.psd1|\.ps1xml' -and
        $_.Name -notmatch "^$env:BHProjectName\.ps[d|m]1$" -and
        $_.Name -notmatch "^module\.requirements\.psd1" -and
        $_.Name -notmatch "^build\.requirements\.psd1" -and
        $_.Name -notmatch "^build\.ps1$" -and
        $_.Name -notmatch $($HelperFilesToSignNameRegex -join '|') -and
        $_.Name -notmatch $RemoveSignatureFilePathRegex -and
        $_.FullName -notmatch "\\Pages\\Dynamic|\\Pages\\Static"
    }
    #$null = $FilesToSign.Add($(Get-Item $env:BHModulePath\Install-PSDepend.ps1))

    Remove-Signature -FilePath $FilesToSign.FullName

    ##### BEGIN Tasks Unique to this Module's Build #####

    ##### END Tasks Unique to this Module's Build #####

    [System.Collections.ArrayList]$FilesFailedToSign = @()
    foreach ($FilePath in $FilesToSign.FullName) {
        try {
            Write-Host "Signing $FilePath..."
            $SetAuthenticodeResult = Set-AuthenticodeSignature -FilePath $FilePath -cert $Cert
            if (!$SetAuthenticodeResult -or $SetAuthenticodeResult.Status -eq "HasMisMatch") {throw}
        }
        catch {
            Write-Warning "Signing $FilePath failed!"
            $null = $FilesFailedToSign.Add($FilePath)
        }
    }

    if ($FilesFailedToSign.Count -gt 0) {
        Write-Error "Halting because we failed to digitally sign the following files:`n$($FilesFailedToSign -join "`n")"
        $global:FunctionResult = "1"
        return
    }
}

#endregion >> Sign Everything

if (!$(Get-Module -ListAvailable PSDepend)) {
    & $(Resolve-Path "$PSScriptRoot\*Help*\Install-PSDepend.ps1").Path
}
try {
    Import-Module PSDepend
    $null = Invoke-PSDepend -Path "$PSScriptRoot\build.requirements.psd1" -Install -Import -Force

    # Hack to fix AppVeyor Error When attempting to Publish to PSGallery
    # The specific error this fixes is a problem with the Publish-Module cmdlet from PowerShellGet. PSDeploy
    # calls Publish-Module without the -Force parameter which results in this error: https://github.com/PowerShell/PowerShellGet/issues/79
    # This is more a problem with PowerShellGet than PSDeploy.
    Remove-Module PSDeploy -ErrorAction SilentlyContinue
    $PSDeployScriptToEdit = Get-Childitem -Path $(Get-Module -ListAvailable PSDeploy).ModuleBase -File -Recurse -Filter "PSGalleryModule.ps1"
    [System.Collections.ArrayList][array]$PSDeployScriptContent = Get-Content $PSDeployScriptToEdit.FullName
    $LineOfInterest = $($PSDeployScriptContent | Select-String -Pattern ".*?Verbose[\s]+= \`$VerbosePreference").Matches.Value
    $IndexOfLineOfInterest = $PSDeployScriptContent.IndexOf($LineOfInterest)
    $PSDeployScriptContent.Insert($($IndexOfLineOfInterest+1),"            Force      = `$True")
    Set-Content -Path $PSDeployScriptToEdit.FullName -Value $PSDeployScriptContent
    Import-Module PSDeploy
}
catch {
    Write-Error $_
    $global:FunctionResult = "1"
    return
}

if ([bool]$(Get-Module -Name $env:BHProjectName -ErrorAction SilentlyContinue)) {
    Remove-Module $env:BHProjectName -Force -ErrorAction SilentlyContinue
}

##### BEGIN Tasks Unique to this Module's Build #####

Remove-Module PowerShellGet -Force -ErrorAction SilentlyContinue
Remove-Module PackageManagement -Force -ErrorAction SilentlyContinue

##### END Tasks Unique to this Module's Build #####

##### END Prepare For Build #####

##### BEGIN PSAKE Build #####

$psakeFile = "$env:BHProjectPath\psake.ps1"
if (!$(Test-Path $psakeFile)) {
    Write-Error "Unable to find the path $psakeFile! Halting!"
    $global:FunctionResult = "1"
    return
}

if ($PSBoundParameters.ContainsKey('help')) {
    Get-PSakeScriptTasks -buildFile $psakeFile | Format-Table -Property Name, Description, Alias, DependsOn
    return
}

# Add any test resources that you want to push to psake.ps1 and/or *.Tests.ps1 files
$TestResources = @{}

$InvokePSakeParams = @{}
if ($Cert) {
    $InvokePSakeParams.Add("Cert",$Cert)
}
if ($TestResources.Count -gt 0) {
    $InvokePSakeParams.Add("TestResources",$TestResources)
}

if ($InvokePSakeParams.Count -gt 0) {
    Invoke-Psake $psakeFile -taskList $Task -nologo -parameters $InvokePSakeParams -ErrorVariable IPSErr
}
else {
    Invoke-Psake $psakeFile -taskList $Task -nologo -ErrorAction Stop
}

# If we're NOT in AppVeyor, we want to sign everything again
if ($env:BHBuildSystem -ne 'AppVeyor') {
    #region >> Sign Everything

    if ($CertFileForSignature -and !$Cert) {
        if (!$(Test-Path $CertFileForSignature)) {
            Write-Error "Unable to find the Certificate specified to be used for Code Signing! Halting!"
            $global:FunctionResult = "1"
            return
        }

        try {
            $Cert = Get-PfxCertificate $CertFileForSignature -ErrorAction Stop
            if (!$Cert) {throw "There was a prblem with the Get-PfcCertificate cmdlet! Halting!"}
        }
        catch {
            Write-Error $_
            $global:FunctionResult = "1"
            return
        }
    }

    if ($Cert) {
        # Make sure the Cert is good for Code Signing
        if ($Cert.EnhancedKeyUsageList.ObjectId -notcontains "1.3.6.1.5.5.7.3.3") {
            $CNOfCert = $($($Cert.Subject -split ",")[0] -replace "CN=","").Trim()
            Write-Error "The provided Certificate $CNOfCert says that it should be sued for $($Cert.EnhancedKeyUsageList.FriendlyName -join ','), NOT 'Code Signing'! Halting!"
            $global:FunctionResult = "1"
            return
        }

        # Make sure our ProtoHelpers are signed before we do anything else, otherwise we won't be able to use them
        $HelperFilestoSign = Get-ChildItem $(Resolve-Path "$PSScriptRoot\*Help*\").Path -Recurse -File | Where-Object {
            $_.Extension -match '\.ps1|\.psm1|\.psd1|\.ps1xml' -and $_.Name -ne "Remove-Signature.ps1"
        }

        # Before we loop through and sign the Helper functions, we need to sign Remove-Signature.ps1
        $RemoveSignatureFilePath = $(Resolve-Path "$PSScriptRoot\*Help*\Remove-Signature.ps1").Path
        if (!$(Test-Path $RemoveSignatureFilePath)) {
            Write-Error "Unable to find the path $RemoveSignatureFilePath! Halting!"
            $global:FunctionResult = "1"
            return
        }

        # Because Set-Authenticode sometimes eats a trailing line when it is used, make sure Remove-Signature.ps1 doesn't break
        $SingatureLineRegex = '^# SIG # Begin signature block|^<!-- SIG # Begin signature block -->'
        $RemoveSignatureContent = Get-Content $RemoveSignatureFilePath
        [System.Collections.ArrayList]$UpdatedRemoveSignatureContent = @()
        foreach ($line in $RemoveSignatureContent) {
            if ($line -match $SingatureLineRegex) {
                $null = $UpdatedRemoveSignatureContent.Add("`n")
                break
            }
            else {
                $null = $UpdatedRemoveSignatureContent.Add($line)
            }
        }
        Set-Content -Path $RemoveSignatureFilePath -Value $UpdatedRemoveSignatureContent

        try {
            $SetAuthenticodeResult = Set-AuthenticodeSignature -FilePath $RemoveSignatureFilePath -Cert $Cert
            if (!$SetAuthenticodeResult -or $SetAuthenticodeResult.Status -ne "Valid") {throw "There was a problem using the Set-AuthenticodeSignature cmdlet to sign the Remove-Signature.ps1 function! Halting!"}
        }
        catch {
            Write-Error $_
            $global:FunctionResult = "1"
            return
        }

        # Dot Source the Remove-Signature function
        . $RemoveSignatureFilePath
        if (![bool]$(Get-Item Function:\Remove-Signature)) {
            Write-Error "Problem dot sourcing the Remove-Signature function! Halting!"
            $global:FunctionResult = "1"
            return
        }

        # Loop through the Help Scripts/Functions and sign them so that we can use them immediately if necessary
        Remove-Signature -FilePath $HelperFilestoSign.FullName

        [System.Collections.ArrayList]$FilesFailedToSign = @()
        foreach ($FilePath in $HelperFilestoSign.FullName) {
            try {
                Write-Host "Signing $FilePath..."
                $SetAuthenticodeResult = Set-AuthenticodeSignature -FilePath $FilePath -cert $Cert
                if (!$SetAuthenticodeResult -or $SetAuthenticodeResult.Status -ne "Valid") {throw}
            }
            catch {
                Write-Warning "Signing $FilePath failed!"
                $null = $FilesFailedToSign.Add($FilePath)
            }
        }

        if ($FilesFailedToSign.Count -gt 0) {
            Write-Error "Halting because we failed to digitally sign the following files:`n$($FilesFailedToSign -join "`n")"
            $global:FunctionResult = "1"
            return
        }
    }

    if ($Cert) {
        # NOTE: We don't want to include the Module's .psm1 or .psd1 yet because the psake.ps1 Compile Task hasn't finalized them yet...
        # NOTE: We don't want to sign build.ps1, Remove-Signature.ps1, or Helper functions because we just did that above...
        $HelperFilesToSignNameRegex = $HelperFilestoSign.Name | foreach {[regex]::Escape($_)}
        $RemoveSignatureFilePathRegex = [regex]::Escape($RemoveSignatureFilePath)
        [System.Collections.ArrayList][array]$FilesToSign = Get-ChildItem $env:BHProjectPath -Recurse -File | Where-Object {
            $_.Extension -match '\.ps1|\.psm1|\.psd1|\.ps1xml' -and
            $_.Name -notmatch "^module\.requirements\.psd1" -and
            $_.Name -notmatch "^build\.requirements\.psd1" -and
            $_.Name -notmatch "^build\.ps1$" -and
            $_.Name -notmatch $($HelperFilesToSignNameRegex -join '|') -and
            $_.Name -notmatch $RemoveSignatureFilePathRegex -and
            $_.FullName -notmatch "\\Pages\\Dynamic|\\Pages\\Static"
        }
        #$null = $FilesToSign.Add($(Get-Item $env:BHModulePath\Install-PSDepend.ps1))

        Remove-Signature -FilePath $FilesToSign.FullName

        ##### BEGIN Tasks Unique to this Module's Build #####

        ##### END Tasks Unique to this Module's Build #####

        [System.Collections.ArrayList]$FilesFailedToSign = @()
        foreach ($FilePath in $FilesToSign.FullName) {
            try {
                Write-Host "Signing $FilePath..."
                $SetAuthenticodeResult = Set-AuthenticodeSignature -FilePath $FilePath -cert $Cert
                if (!$SetAuthenticodeResult -or $SetAuthenticodeResult.Status -eq "HasMisMatch") {throw}
            }
            catch {
                Write-Warning "Signing $FilePath failed!"
                $null = $FilesFailedToSign.Add($FilePath)
            }
        }

        if ($FilesFailedToSign.Count -gt 0) {
            Write-Error "Halting because we failed to digitally sign the following files:`n$($FilesFailedToSign -join "`n")"
            $global:FunctionResult = "1"
            return
        }
    }

    #endregion >> Sign Everything
}

exit ( [int]( -not $psake.build_success ) )

##### END PSAKE Build #####


# SIG # Begin signature block
# MIIMaAYJKoZIhvcNAQcCoIIMWTCCDFUCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUZ1Ikq65ywWPdxTLIM8o4FgXx
# 7VGgggndMIIEJjCCAw6gAwIBAgITawAAAERR8umMlu6FZAAAAAAARDANBgkqhkiG
# 9w0BAQsFADAwMQwwCgYDVQQGEwNMQUIxDTALBgNVBAoTBFpFUk8xETAPBgNVBAMT
# CFplcm9EQzAxMB4XDTE5MTEyODEyMjgyNloXDTIxMTEyODEyMzgyNlowPTETMBEG
# CgmSJomT8ixkARkWA0xBQjEUMBIGCgmSJomT8ixkARkWBFpFUk8xEDAOBgNVBAMT
# B1plcm9TQ0EwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQC0crvKbqlk
# 77HGtaVMWpZBOKwb9eSHzZjh5JcfMJ33A9ORwelTAzpRP+N0k/rAoQkauh3qdeQI
# fsqdcrEiingjiOvxaX3lHA5+fVGe/gAnZ+Cc7iPKXJVhw8jysCCld5zIG8x8eHuV
# Z540iNXdI+g2mustl+l5q4kcWukj+iQwtCYEaCgAXB9qlkT33sX0k/07JoSYcGJx
# ++0SHnF0HBw7Gs/lHlyt4biIGtJleOw0iIN2yVD9UrVWMtKrghKPaW31mjYYeN5k
# ckYzBit/Kokxo0m54B4M3aLRPBQdXH1wL6A894BAlUlPM7vrozU2cLrZgcFuEvwM
# 0cLN8mfGKbo5AgMBAAGjggEqMIIBJjASBgkrBgEEAYI3FQEEBQIDAgADMCMGCSsG
# AQQBgjcVAgQWBBQIf0JBlAvGtUeDPLbljq9G8OOkkzAdBgNVHQ4EFgQUkNLPVlgd
# vV0pNGjQxY8gU/mxzMIwGQYJKwYBBAGCNxQCBAweCgBTAHUAYgBDAEEwDgYDVR0P
# AQH/BAQDAgGGMA8GA1UdEwEB/wQFMAMBAf8wHwYDVR0jBBgwFoAUdpW6phL2RQNF
# 7AZBgQV4tgr7OE0wMQYDVR0fBCowKDAmoCSgIoYgaHR0cDovL3BraS9jZXJ0ZGF0
# YS9aZXJvREMwMS5jcmwwPAYIKwYBBQUHAQEEMDAuMCwGCCsGAQUFBzAChiBodHRw
# Oi8vcGtpL2NlcnRkYXRhL1plcm9EQzAxLmNydDANBgkqhkiG9w0BAQsFAAOCAQEA
# WObmEzp48rKuXiJ628N7F/clqVVG+dl6UNCrPGK/fr+TbEE3RFpsPfd166gTFF65
# 5ZEbas8qW11makxfIL41GykCZSHMCJBhFhh68xnBSsplemm2CAb06+j2dkuvmOR3
# Aa9+ujtW8eSgNcSr3dkYa3fZfV3siTaY+9FmEWH8D0tglEUuUv1+KPAwXRvdNN7f
# pAsyL5qq/canjqR6/BmLSXdoD3LPISDH/iZpboBwCrhy+imupusnxjZdYFP/Siox
# g7dbvcSkr05t6jlr8xABrU+zzK3yUol/WHOnE70krG3JONBO3kN+Jv/hktIt5pd6
# imtXSPImm4BUPGa7ppeVNDCCBa8wggSXoAMCAQICE1gAAAJQw22Yn6op/pMAAwAA
# AlAwDQYJKoZIhvcNAQELBQAwPTETMBEGCgmSJomT8ixkARkWA0xBQjEUMBIGCgmS
# JomT8ixkARkWBFpFUk8xEDAOBgNVBAMTB1plcm9TQ0EwHhcNMTkxMTI4MTI1MDM2
# WhcNMjExMTI3MTI1MDM2WjBJMUcwRQYDVQQDEz5aZXJvQ29kZTEzLE9VPURldk9w
# cyxPPVRlY2ggVGFyZ2V0cywgTExDLEw9QnJ5biBNYXdyLFM9UEEsQz1VUzCCASIw
# DQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAPYULq1HCD/SgqTajXuWjnzVedBE
# Nc3LQwdDFmOLyrVPi9S9FF3yYDCTywA6wwgxSQGhI8MVWwF2Xdm+e6pLX+957Usk
# /lZGHCNwOMP//vodJUhxcyDZG7sgjjz+3qBl0OhUodZfqlprcVMQERxlIK4djDoP
# HhIBHBm6MZyC9oiExqytXDqbns4B1MHMMHJbCBT7KZpouonHBK4p5ObANhGL6oh5
# GnUzZ+jOTSK4DdtulWsvFTBpfz+JVw/e3IHKqHnUD4tA2CxxA8ofW2g+TkV+/lPE
# 9IryeA6PrAy/otg0MfVPC2FKaHzkaaMocnEBy5ZutpLncwbwqA3NzerGmiMCAwEA
# AaOCApowggKWMA4GA1UdDwEB/wQEAwIHgDAdBgNVHQ4EFgQUW0DvcuEW1X6BD+eQ
# 2AJHO2eur9UwHwYDVR0jBBgwFoAUkNLPVlgdvV0pNGjQxY8gU/mxzMIwgekGA1Ud
# HwSB4TCB3jCB26CB2KCB1YaBrmxkYXA6Ly8vQ049WmVyb1NDQSgyKSxDTj1aZXJv
# U0NBLENOPUNEUCxDTj1QdWJsaWMlMjBLZXklMjBTZXJ2aWNlcyxDTj1TZXJ2aWNl
# cyxDTj1Db25maWd1cmF0aW9uLERDPXplcm8sREM9bGFiP2NlcnRpZmljYXRlUmV2
# b2NhdGlvbkxpc3Q/YmFzZT9vYmplY3RDbGFzcz1jUkxEaXN0cmlidXRpb25Qb2lu
# dIYiaHR0cDovL3BraS9jZXJ0ZGF0YS9aZXJvU0NBKDIpLmNybDCB5gYIKwYBBQUH
# AQEEgdkwgdYwgaMGCCsGAQUFBzAChoGWbGRhcDovLy9DTj1aZXJvU0NBLENOPUFJ
# QSxDTj1QdWJsaWMlMjBLZXklMjBTZXJ2aWNlcyxDTj1TZXJ2aWNlcyxDTj1Db25m
# aWd1cmF0aW9uLERDPXplcm8sREM9bGFiP2NBQ2VydGlmaWNhdGU/YmFzZT9vYmpl
# Y3RDbGFzcz1jZXJ0aWZpY2F0aW9uQXV0aG9yaXR5MC4GCCsGAQUFBzAChiJodHRw
# Oi8vcGtpL2NlcnRkYXRhL1plcm9TQ0EoMykuY3J0MD0GCSsGAQQBgjcVBwQwMC4G
# JisGAQQBgjcVCIO49D+Em/J5g/GPOIOwtzKG0c14gSeh88wfj9lVAgFkAgEFMBMG
# A1UdJQQMMAoGCCsGAQUFBwMDMBsGCSsGAQQBgjcVCgQOMAwwCgYIKwYBBQUHAwMw
# DQYJKoZIhvcNAQELBQADggEBAEfjH/emq+TnlhFss6cNor/VYKPoEeqYgFwzGbul
# dzPdPEBFUNxcreN0b61kxfenAHifvI0LCr/jDa8zGPEOvo8+zB/GWp1Huw/xLMB8
# rfZHBCox3Av0ohjzO5Ac5yCHijZmrwaXV3XKpBncWdC6pfr/O0bIoRMbvV9EWkYG
# fpNaFvR8piUGJ47cLlC+NFTOQcmESOmlsy+v8JeG9OPsnvZLsD6sydajrxRnNlSm
# zbK64OrbSM9gQoA6bjuZ6lJWECCX1fEYDBeZaFrtMB/RTVQLF/btisfDQXgZJ+Tw
# Tjy+YP39D0fwWRfAPSRJ8NcnRw4Ccj3ngHz7e0wR6niCtsMxggH1MIIB8QIBATBU
# MD0xEzARBgoJkiaJk/IsZAEZFgNMQUIxFDASBgoJkiaJk/IsZAEZFgRaRVJPMRAw
# DgYDVQQDEwdaZXJvU0NBAhNYAAACUMNtmJ+qKf6TAAMAAAJQMAkGBSsOAwIaBQCg
# eDAYBgorBgEEAYI3AgEMMQowCKACgAChAoAAMBkGCSqGSIb3DQEJAzEMBgorBgEE
# AYI3AgEEMBwGCisGAQQBgjcCAQsxDjAMBgorBgEEAYI3AgEVMCMGCSqGSIb3DQEJ
# BDEWBBSLjQpkEvkbwxM8OPrw5WQFoDdQrDANBgkqhkiG9w0BAQEFAASCAQBjQ0ka
# /dLn1eOOiQrxA14MXNCXAS3FUdZAUuSwU0Cuizw9/D92OlFJsOwH7N2Cew06foso
# UmPieFxmyeNTgNP9xGkexYlARndKNoIjwAce5wKC2OHBDVPznqdb3InwApzJ3WMh
# 3lZ5vY2qykY89miW3hBQOPH6PkdztUL/KgVWI2h8i4tJvFPI8v5qDp5nNBWO6SYQ
# v0T6qCQNH4ksLbkHfDBGB7JqGV8KGnwVZ0ARGeC72gVIUrSt8RQ090oOmbZbwvRl
# G2vI/1DZzsSpk+BFpm8+kZMRhaIejSQkFoj1leN9Nmhgq32jVOWJvIQzgIVJ485I
# hlwkBgXsE/s1faNc
# SIG # End signature block
