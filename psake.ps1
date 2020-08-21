[CmdletBinding()]
param(
    [Parameter(Mandatory=$False)]
    [System.Security.Cryptography.X509Certificates.X509Certificate2]$Cert,

    [Parameter(Mandatory=$False)]
    [System.Collections.Hashtable]$TestResources
)

# NOTE: `Set-BuildEnvironment -Force -Path $PSScriptRoot` from build.ps1 makes the following $env: available:
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
#>

# NOTE: If -TestResources was used, the folloqing resources should be available
<#
    $TestResources = @{
        UserName        = $UserName
        SimpleUserName  = $SimpleUserName
        Password        = $Password
        Creds           = $Creds
    }
#>

# PSake makes variables declared here available in other scriptblocks
# Init some things
Properties {
    $PublicScriptFiles = Get-ChildItem "$env:BHModulePath\Public" -File -Filter *.ps1 -Recurse
    $PrivateScriptFiles = Get-ChildItem -Path "$env:BHModulePath\Private" -File -Filter *.ps1 -Recurse

    $Timestamp = Get-Date -UFormat "%Y%m%d-%H%M%S"
    $PSVersion = $PSVersionTable.PSVersion.Major
    $TestFile = "TestResults_PS$PSVersion`_$TimeStamp.xml"
    $lines = '----------------------------------------------------------------------'

    $Verbose = @{}
    if ($ENV:BHCommitMessage -match "!verbose") {
        $Verbose = @{Verbose = $True}
    }

    if ($Cert) {
        # Need to Declare $Cert here in the 'Properties' block so that it's available in other script blocks
        $Cert = $Cert
    }
}

Task Default -Depends Test

Task Init -RequiredVariables  {
    $lines
    Set-Location $ProjectRoot
    "Build System Details:"
    Get-Item ENV:BH*
    "`n"
}

Task Compile -Depends Init {
    $BoilerPlateFunctionSourcing = @'
$ThisModule = $(Get-Item $PSCommandPath).BaseName

<#
if (!$IsWindows) {
    Write-Error "This $ThisModule must be run on PowerShell 6 or higher on a Windows operating system! Halting!"
    return
}
#>

[Net.ServicePointManager]::SecurityProtocol = "tls12, tls11, tls"

# Get public and private function definition files.
[array]$Public  = Get-ChildItem -Path "$PSScriptRoot\Public\*.ps1" -ErrorAction SilentlyContinue
[array]$Private = Get-ChildItem -Path "$PSScriptRoot\Private\*.ps1" -ErrorAction SilentlyContinue


# Dot source the Private functions
foreach ($import in $Private) {
    try {
        . $import.FullName
    }
    catch {
        Write-Error -Message "Failed to import function $($import.FullName): $_"
    }
}

[System.Collections.Arraylist]$ModulesToInstallAndImport = @()
if (Test-Path "$PSScriptRoot\module.requirements.psd1") {
    $ModuleManifestDataPrep = Import-PowerShellDataFile "$PSScriptRoot\module.requirements.psd1"
    $ModuleManifestDataPrep.Keys | Where-Object {$_ -ne "PSDependOptions"} | foreach {$null = $ModulesToinstallAndImport.Add($_)}
    $ModuleManifestData = $($ModuleManifestDataPrep.GetEnumerator()) | Where-Object {$_.Name -ne "PSDependOptions"}
}

if ($ModulesToInstallAndImport.Count -gt 0) {
    # Set $env:PSModulePath correctly
    # Determine installed PowerShell Core Versions
    $PSCoreDirItems = @(Get-ChildItem -Path "$env:ProgramFiles\Powershell" -Directory | Where-Object {$_.Name -match "[0-9]"})
    $LatestPSCoreDirPath = $($PSCoreDirItems | Sort-Object -Property CreationTime)[-1].FullName
    $PSCoreUserDocsModulePath = "$HOME\Documents\PowerShell\Modules"
    $WinPSUserDocsModulePath = "$HOME\Documents\WindowsPowerShell\Modules"
    $LatestPSCoreSystemPath = "$LatestPSCoreDirPath\Modules"
    $LatestWinPSSystemPath = "$env:ProgramFiles\WindowsPowerShell\Modules"

    $PSCoreModulePaths = @(
        $PSCoreUserDocsModulePath
        $($LatestPSCoreDirPath | Split-Path -Parent)
        $LatestPSCoreSystemPath
    )
    $WinPSModulePaths = @(
        $WinPSUserDocsModulePath
        $LatestWinPSSystemPath
        "$env:SystemRoot\system32\WindowsPowerShell\v1.0\Modules"
    )

    $AllPSModulePaths = [System.Collections.Generic.List[object]]::new()
    $PSCoreModulePaths | foreach {$AllPSModulePaths.Add($_)}
    $WinPSModulePaths | foreach {$AllPSModulePaths.Add($_)}

    <#
    foreach ($ModPath in $AllPSModulePaths) {
        if (![bool]$($($env:PSModulePath -split ";") -match [regex]::Escape($ModPath))) {
            $env:PSModulePath = "$ModPath;$env:PSModulePath"
        }
    }
    #>

    # Attempt to import the Module Dependencies
    foreach ($ModuleData in $ModuleManifestData) {
        $ModuleName = $ModuleData.Name

        # Make sure it's installed
        $GetModResult = [System.Collections.Generic.List[object]]::new()
        @(Get-Module -ListAvailable -Name $ModuleName) | foreach {$GetModResult.Add($_)}
        if ($PSVersionTable.PSEdition -eq "Core" -and $ModuleData.Value.PSVersion -eq "Core") {
            foreach ($ModPath in $PSCoreModulePaths) {
                if (Test-Path $ModPath) {
                    $ModuleDir = Get-ChildItem -Path $ModPath -Directory | Where-Object {$_.Name -eq $ModuleName}
                    if ($ModuleDir) {$GetModResult.Add($ModuleDir)}
                }
            }
        }
        if ($($PSVersionTable.PSEdition -eq "Desktop" -and $ModuleData.Value.PSVersion -eq "WinPS") -or $($PSVersionTable.PSEdition -eq "Core" -and $ModuleData.Value.PSVersion -eq "WinPS")) {
            foreach ($ModPath in $WinPSModulePaths) {
                if (Test-Path $ModPath) {
                    $ModuleDir = Get-ChildItem -Path $ModPath -Directory | Where-Object {$_.Name -eq $ModuleName}
                    if ($ModuleDir) {$GetModResult.Add($ModuleDir)}
                }
            }
        }
        if ($ModuleData.Value.PSVersion -eq "WinPSAndPSCore") {
            foreach ($ModPath in $AllPSModulePaths) {
                if (Test-Path $ModPath) {
                    $ModuleDir = Get-ChildItem -Path $ModPath -Directory | Where-Object {$_.Name -eq $ModuleName}
                    if ($ModuleDir) {$GetModResult.Add($ModuleDir)}
                }
            }
        }

        if ($GetModResult.Count -eq 0) {
            try {
                if ($ModuleData.Value.PSVersion -eq "WinPS" -and $PSVersionTable.PSEdition -eq "Core") {
                    powershell.exe -NoProfile -NoLogo -NonInteractive -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Install-Module $ModuleName -Scope CurrentUser -AllowClobber -Force"
                }
                if ($($ModuleData.Value.PSVersion -eq "PSCore" -and $PSVersionTable.PSEdition -eq "Core") -or $PSVersionTable.PSEdition -eq "Desktop") {
                    $null = Install-Module -Name $ModuleName -Scope CurrentUser -AllowClobber -Force -ErrorAction Stop -WarningAction SilentlyContinue
                }
                if ($ModuleData.Value.PSVersion -eq "WinPSAndPSCore" -and $PSVersionTable.PSEdition -eq "Core") {
                    powershell.exe -NoProfile -NoLogo -NonInteractive -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Install-Module $ModuleName -Scope CurrentUser -AllowClobber -Force"
                    $null = Install-Module -Name $ModuleName -Scope CurrentUser -AllowClobber -Force -ErrorAction Stop -WarningAction SilentlyContinue
                }
            }
            catch {
                $Msg = "Problem installing Module dependency $ModuleName : " + $_.Exception.Message
                Write-Error $Msg
                return
            }

            # Check again to make sure it's installed
            $GetModResult = [System.Collections.Generic.List[object]]::new()
            @(Get-Module -ListAvailable -Name $ModuleName) | foreach {$GetModResult.Add($_)}
            if ($PSVersionTable.PSEdition -eq "Core" -and $ModuleData.Value.PSVersion -eq "Core") {
                foreach ($ModPath in $PSCoreModulePaths) {
                    if (Test-Path $ModPath) {
                        $ModuleDir = Get-ChildItem -Path $ModPath -Directory | Where-Object {$_.Name -eq $ModuleName}
                        if ($ModuleDir) {$GetModResult.Add($ModuleDir)}
                    }
                }
            }
            if ($($PSVersionTable.PSEdition -eq "Desktop" -and $ModuleData.Value.PSVersion -eq "WinPS") -or $($PSVersionTable.PSEdition -eq "Core" -and $ModuleData.Value.PSVersion -eq "WinPS")) {
                foreach ($ModPath in $WinPSModulePaths) {
                    if (Test-Path $ModPath) {
                        $ModuleDir = Get-ChildItem -Path $ModPath -Directory | Where-Object {$_.Name -eq $ModuleName}
                        if ($ModuleDir) {$GetModResult.Add($ModuleDir)}
                    }
                }
            }
            if ($ModuleData.Value.PSVersion -eq "WinPSAndPSCore") {
                foreach ($ModPath in $AllPSModulePaths) {
                    if (Test-Path $ModPath) {
                        $ModuleDir = Get-ChildItem -Path $ModPath -Directory | Where-Object {$_.Name -eq $ModuleName}
                        if ($ModuleDir) {$GetModResult.Add($ModuleDir)}
                    }
                }
            }

            if ($GetModResult.Count -eq 0) {
                Write-Error "Problem installing Module dependency $ModuleName ! Halting!"
                return
            }
        }
        
        # Import the Module
        if ($ModuleData.Value.PSVersion -eq "WinPS" -or $ModuleData.Value.PSVersion -eq "WinPSAndPSCore") {
            try {
                if ($PSVersionTable.PSEdition -eq 'Core') {
                    Import-Module $ModuleName -UseWindowsPowerShell -ErrorAction Stop
                } else {
                    Import-Module $ModuleName -ErrorAction Stop
                }
            } catch {
                $Msg = "Problem importing Module dependency $ModuleName : " + $_.Exception.Message
                Write-Error $Msg
                return
            }
        }
        else {
            try {
                Import-Module -Name $ModuleName -ErrorAction Stop
            }
            catch {
                $Msg = "Problem importing Module dependency $ModuleName : " + $_.Exception.Message
                Write-Error $Msg
                return
            }
        }

        # Alternate Module Import Logic (that assumes $ThisModule is compatible with WinPS and PSCore)
        <#
        try {
            Import-Module -Name $ModuleName -ErrorAction Stop
        }
        catch {
            # If we're in PSCore, then we need to potentially try the -UseWindowsPowerShell switch
            if ($PSVersionTable.PSEdition -eq "Core") {
                try {
                    Import-Module -Name $ModuleName -UseWindowsPowerShell -ErrorAction Stop
                }
                catch {
                    Write-Error "Problem importing Module dependency $ModuleName ! Halting!"
                    return
                }
            }
            else {
                Write-Error "Problem importing Module dependency $ModuleName ! Halting!"
                return
            }
        }
        #>
    }
}

# Public Functions

'@
    Set-Content -Path "$env:BHModulePath\$env:BHProjectName.psm1" -Value $BoilerPlateFunctionSourcing

    [System.Collections.ArrayList]$FunctionTextToAdd = @()
    foreach ($ScriptFileItem in $PublicScriptFiles) {
        $FileContent = Get-Content $ScriptFileItem.FullName
        $SigBlockLineNumber = $FileContent.IndexOf('# SIG # Begin signature block')
        $FunctionSansSigBlock = $($($FileContent[0..$($SigBlockLineNumber-1)]) -join "`n").Trim() -split "`n"
        $null = $FunctionTextToAdd.Add("`n")
        $null = $FunctionTextToAdd.Add($FunctionSansSigBlock)
    }
    $null = $FunctionTextToAdd.Add("`n")

    Add-Content -Value $FunctionTextToAdd -Path "$env:BHModulePath\$env:BHProjectName.psm1"

    # Finally, add array the variables contained in VariableLibrary.ps1 if it exists in case we want to use this Module Remotely
    if (Test-Path "$env:BHModulePath\VariableLibrary.ps1") {
        Get-Content "$env:BHModulePath\VariableLibrary.ps1" | Add-Content "$env:BHModulePath\$env:BHProjectName.psm1"
    }

    if ($Cert) {
        # At this point the .psm1 is finalized, so let's sign it
        try {
            $SetAuthenticodeResult = Set-AuthenticodeSignature -FilePath "$env:BHModulePath\$env:BHProjectName.psm1" -cert $Cert
            if (!$SetAuthenticodeResult -or $SetAuthenticodeResult.Status -eq "HashMisMatch") {throw}
        }
        catch {
            Write-Error "Failed to sign '$ModuleName.psm1' with Code Signing Certificate! Invoke-Pester will not be able to load '$ModuleName.psm1'! Halting!"
            $global:FunctionResult = "1"
            return
        }
    }
}

Task Test -Depends Compile  {
    $lines
    "`n`tSTATUS: Testing with PowerShell $PSVersion"

    $PesterSplatParams = @{
        PassThru        = $True
        OutputFormat    = "NUnitXml"
        OutputFile      = "$env:BHBuildOutput\$TestFile"
    }
    if ($TestResources) {
        $ScriptParamHT = @{
            Path = "$env:BHProjectPath\Tests"
            Parameters = @{TestResources = $TestResources}
        }
        $PesterSplatParams.Add("Script",$ScriptParamHT)
    }
    else {
        $PesterSplatParams.Add("Path","$env:BHProjectPath\Tests")
    }

    # Gather test results. Store them in a variable and file
    $TestResults = Invoke-Pester @PesterSplatParams

    # Make sure Authenticode Signature has been removed
    $RemoveSignatureFilePath = $(Resolve-Path "$PSScriptRoot\*Help*\Remove-Signature.ps1").Path
    $RemoveSignatureFilePathRegex = [regex]::Escape($RemoveSignatureFilePath)
    . $RemoveSignatureFilePath
    if (![bool]$(Get-Item Function:\Remove-Signature)) {
        Write-Error "Problem dot sourcing the Remove-Signature function! Halting!"
        $global:FunctionResult = "1"
        return
    }
    [System.Collections.ArrayList][array]$HelperFilestoSign = Get-ChildItem $(Resolve-Path "$PSScriptRoot\*Help*\").Path -Recurse -File | Where-Object {
        $_.Extension -match '\.ps1|\.psm1|\.psd1|\.ps1xml' -and $_.Name -ne "Remove-Signature.ps1"
    }
    foreach ($FileItem in $HelperFilestoSign) {
        if ($(Get-AuthenticodeSignature -FilePath $FileItem.FullName) -ne "NotSigned") {
            Write-Host "Removing signature from $($FileItem.FullName)..."
            Remove-Signature -FilePath $FileItem.FullName
        }
    }

    $HelperFilesToSignNameRegex = $HelperFilestoSign.Name | foreach {[regex]::Escape($_)}

    [System.Collections.ArrayList][array]$FilesToSign = Get-ChildItem $env:BHProjectPath -Recurse -File | Where-Object {
        $_.Extension -match '\.ps1|\.psm1|\.psd1|\.ps1xml' -and
        $_.Name -notmatch "^build\.ps1$" -and
        $_.Name -notmatch $($HelperFilesToSignNameRegex -join '|') -and
        $_.Name -notmatch $RemoveSignatureFilePathRegex -and
        $_.FullName -notmatch "\\Pages\\Dynamic|\\Pages\\Static" -and
        $_.Name -notmatch "psake\.ps1" -and
        $_.Name -notmatch "Tests\.ps1"
    }
    foreach ($FileItem in $FilestoSign) {
        if ($(Get-AuthenticodeSignature -FilePath $FileItem.FullName) -ne "NotSigned") {
            Write-Host "Removing signature from $($FileItem.FullName)..."
            Remove-Signature -FilePath $FileItem.FullName
        }
    }

    # In Appveyor?  Upload our tests! #Abstract this into a function?
    if ($env:BHBuildSystem -eq 'AppVeyor') {
        (New-Object 'System.Net.WebClient').UploadFile(
            "https://ci.appveyor.com/api/testresults/nunit/$($env:APPVEYOR_JOB_ID)",
            "$env:BHBuildOutput\$TestFile" )
    }

    Remove-Item "$env:BHBuildOutput\$TestFile" -Force -ErrorAction SilentlyContinue

    # Failed tests?
    # Need to tell psake or it will proceed to the deployment. Danger!
    if ($TestResults.FailedCount -gt 0) {
        Write-Error "Failed '$($TestResults.FailedCount)' tests, build failed"
    }
    "`n"
}

Task Build -Depends Test {
    $lines
    
    # Load the module, read the exported functions, update the psd1 FunctionsToExport
    Set-ModuleFunctions

    # Bump the module version if we didn't already
    Try
    {
        [version]$GalleryVersion = Get-NextNugetPackageVersion -Name $env:BHProjectName -ErrorAction Stop
        #[version]$GalleryVersion = Get-NextPSGalleryVersion -Name $env:BHProjectName -ErrorAction Stop
        [version]$GithubVersion = Get-MetaData -Path $env:BHPSModuleManifest -PropertyName ModuleVersion -ErrorAction Stop
        if($GalleryVersion -ge $GithubVersion) {
            Update-Metadata -Path $env:BHPSModuleManifest -PropertyName ModuleVersion -Value $GalleryVersion -ErrorAction stop
        }
    }
    Catch
    {
        "Failed to update version for '$env:BHProjectName': $_.`nContinuing with existing version"
    }
}

Task Deploy -Depends Build {
    $lines

    $Params = @{
        Path = $PSScriptRoot
        Force = $true
        Recurse = $false
    }
    Invoke-PSDeploy @Verbose @Params
}

# SIG # Begin signature block
# MIIMaAYJKoZIhvcNAQcCoIIMWTCCDFUCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQULJtNzJaw+Hj85CiJMlct/HJW
# 1NOgggndMIIEJjCCAw6gAwIBAgITawAAAERR8umMlu6FZAAAAAAARDANBgkqhkiG
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
# BDEWBBT3naD/IX7w7/5jZiEO6VBovW1qBDANBgkqhkiG9w0BAQEFAASCAQA7H8io
# gi+FQPLuoUKPue45tEXTAMcxjHTUUV2rEng5chkt2bPBMDmeCTSZ9FIAR+Ex50qN
# /3QFqpyGTX1ZuY1M9rTrFL5aA4YStRbd5SYYQ+IDNuTNnhXhcvjvts6xhAStAmUM
# WfOJ/F/SFwFnsVBMfrB337xo3ZSfiSIXvPw0rup68/nU6BvXL9d7XkWd80xZtKsR
# N4iQutWwHzZLVbRgsxkr5s7T5wJJ10tMB6wcvYH1BbizP9DFKtUEKw/6FVebSoAG
# h33pnumBp+wQv6vn/2sasehTM7eMyy7j0MWC1lXkXCbNRqvINbyhPVaDSZHUpynS
# TTij1KXT43QwHdgo
# SIG # End signature block
