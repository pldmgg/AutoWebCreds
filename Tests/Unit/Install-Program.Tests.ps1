[CmdletBinding()]
param(
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

<#
# Load CustomAssertions.psm1
Import-Module "$env:BHProjectPath\Tests\CustomAssertions.psm1" -Force
Add-AssertionOperator -Name 'BeTypeOrType' -Test $Function:BeTypeOrType

# Make sure the Module is loaded
if ([bool]$(Get-Module -Name $env:BHProjectName -ErrorAction SilentlyContinue)) {
    Remove-Module $env:BHProjectName -Force
}
if (![bool]$(Get-Module -Name $env:BHProjectName -ErrorAction SilentlyContinue)) {
    Import-Module $env:BHPSModuleManifest -Force
}

Remove-Module PowerShellGet -Force -ErrorAction SilentlyContinue
Remove-Module PackageManagement -Force -ErrorAction SilentlyContinue
try {
    Import-Module PackageManagement -ErrorAction Stop
}
catch {
    Write-Error $_
    Write-Error "Problem importing the PowerShell Module PackageManagement! Halting!"
    $global:FunctionResult = "1"
    return
}
try {
    Import-Module PowerShellGet -ErrorAction Stop
}
catch {
    Write-Error $_
    Write-Error "Problem importing the PowerShell Module PowerShellGet! Halting!"
    $global:FunctionResult = "1"
    return
}

$InstallManagerValidOutputs = @("choco.exe","PowerShellGet")
$InstallActionValidOutputs = @("Updated","FreshInstall")
$InstallCheckValidOutputs = @($([Microsoft.PackageManagement.Packaging.SoftwareIdentity]::new()),"openssh")
$FinalExeLocation = "C:\Program Files\OpenSSH-Win64\ssh.exe"
$OriginalSystemPath = $(Get-ItemProperty -Path 'Registry::HKEY_LOCAL_MACHINE\System\CurrentControlSet\Control\Session Manager\Environment' -Name PATH).Path
$CurrentSystemPath = $OriginalSystemPath
$OriginalEnvPath = $env:Path
$CurrentSystemPath = $OriginalEnvPath

$FakeOutputHT = [ordered]@{
    InstallManager      = $InstallManagerValidOutputs[1]
    InstallAction       = $InstallActionValidOutputs[1]
    InstallCheck        = $InstallCheckValidOutputs[0]
    MainExecutable      = $FinalExeLocation
    OriginalSystemPath  = $OriginalSystemPath
    CurrentSystemPath   = $CurrentSystemPath
    OriginalEnvPath     = $OriginalEnvPath
    CurrentEnvPath      = $env:Path
}

function CommonTestSeries {
    Param (
        [Parameter(
            Mandatory=$True,
            ValueFromPipeline=$True
        )]
        $InputObject
    )

    it "Should return some kind of output" {
        $InputObject | Assert-NotNull
    }

    it "Should return a PSCustomObject" {
        $InputObject | Assert-Type System.Management.Automation.PSCustomObject
    }

    it "Should return a PSCustomObject with Specific Properties" {
        [System.Collections.ArrayList][array]$ActualPropertiesArray = $($InputObject | Get-Member -MemberType NoteProperty).Name
        [System.Collections.ArrayList][array]$ExpectedPropertiesArray = $global:MockResources['FakeOutputHT'].Keys
        if ($ActualPropertiesArray -contains "PossibleMainExecutables") {
            $ActualPropertiesArray.Remove("PossibleMainExecutables")
            $ExpectedPropertiesArray.Remove("MainExecutable")
        }
        foreach ($Item in $ExpectedPropertiesArray) {
            $ActualPropertiesArray -contains $Item | Assert-True
        }
    }

    it "Should return a PSCustomObject Property InstallManager of Type System.String" {
        $InputObject.InstallManager | Assert-Type System.String
    }

    it "Should return a PSCustomObject Property InstallAction of Type System.String" {
        $InputObject.InstallAction | Assert-Type System.String
    }

    it "Should return a PSCustomObject Property InstallCheck of Type Microsoft.PackageManagement.Packaging.SoftwareIdentity OR System.String" {
        $InputObject.InstallCheck | Should -BeTypeOrType @("Microsoft.PackageManagement.Packaging.SoftwareIdentity","System.String")
    }

    it "Should return a PSCustomObject Property MainExecutable of Type System.String or Null" {
        $InputObject.MainExecutable | Should -BeTypeOrType @("System.String",$null)
    }

    it "Should return a PSCustomObject Property OriginalSystemPath of Type System.String" {
        $InputObject.OriginalSystemPath | Assert-Type System.String
    }

    it "Should return a PSCustomObject Property CurrentSystemPath of Type System.String" {
        $InputObject.CurrentSystemPath | Assert-Type System.String
    }

    it "Should return a PSCustomObject Property OriginalEnvPath of Type System.String" {
        $InputObject.OriginalEnvPath | Assert-Type System.String
    }

    it "Should return a PSCustomObject Property CurrentEnvPath of Type System.String" {
        $InputObject.CurrentEnvPath | Assert-Type System.String
    }
}

function Cleanup {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory=$True)]
        [string]$ProgramName
    )

    Uninstall-Program -ProgramName $ProgramName
}

function StartTesting {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory=$True)]
        $SplatParamsSeriesItem,

        [Parameter(Mandatory=$True)]
        $ContextString
    )

    $global:MockResources['Functions'] | foreach { Invoke-Expression $_ }
    $IPSplatParams = $SplatParamsSeriesItem.TestSeriesSplatParams
    $PrgName = $SplatParamsSeriesItem.TestSeriesSplatParams['ProgramName']

    try {
        $null = Install-Program @IPSplatParams -OutVariable "InstallProgramResult" -ErrorAction Stop

        # Cleanup
        # NOTE: Using -EA SilentlyContinue for Remove-SudoSession because if we error, want to be sure it's from Install-Program
        $null = Cleanup -ProgramName $PrgName -ErrorAction SilentlyContinue
    }
    catch {
        # NOTE: Using Warning to output error message because any Error will prevent the rest of this Context block from running
        Write-Warning $($_.Exception.Message)
        
        $null = Cleanup -ProgramName $PrgName -ErrorAction SilentlyContinue
    }

    if ($InstallProgramResult) {
        switch ($SplatParamsSeriesItem.TestSeriesFunctionNames) {
            'CommonTestSeries' { $InstallProgramResult | CommonTestSeries }
        }
    }
    else {
        Write-Warning "Unable to run 'CommonTestSeries' in Context...`n    '$ContextString'`nbecause the 'Install-Program' function failed to output an object!"
    }
}

$Functions = @(
    ${Function:Cleanup}.Ast.Extent.Text
    ${Function:CommonTestSeries}.Ast.Extent.Text
    ${Function:StartTesting}.Ast.Extent.Text
)

$TestSplatParams = @(
    @{
        ProgramName         = "openssh"
        ResolveCommandPath  = $False
    }

    @{
        ProgramName         = "openssh"
        ResolveCommandPath  = $True
    }

    @{
        ProgramName     = "openssh"
        CommandName     = "ssh"
    }

    @{
        ProgramName                     = "openssh"
        CommandName                     = "ssh"
        ScanCDriveForMainExeIfNecessary = $True
    }

    @{
        ProgramName     = "openssh"
        CommandName     = "ssh"
        PreRelease      = $True
    }

    @{
        ProgramName             = "openssh"
        CommandName             = "ssh"
        ResolveCommandPath      = $False
    }

    @{
        ProgramName             = "openssh"
        CommandName             = "ssh"
        ExpectedInstallLocation = "C:\Program Files\OpenSSH-Win64"
    }

    @{
        ProgramName         = "openssh"
        CommandName         = "ssh"
        UsePowerShellGet    = $True
    }

    @{
        ProgramName             = "openssh"
        CommandName             = "ssh"
        UsePowerShellGet        = $True
        ForceChocoInstallScript = $True
    }

    @{
        ProgramName             = "openssh"
        CommandName             = "ssh"
        UseChocolateyCmdLine    = $True
    }
)

$ProgramAndCmdNameString = "-ProgramName '$($TestSplatParams[0]['ProgramName'])' -CommandName '$($TestSplatParams[0]['ProgramName'])'" 
$SplatParamsSeries = @(
    [pscustomobject]@{
        TestSeriesName          = "ProgramName"
        TestSeriesDescription   = "Test output using: -ProgramName '$($TestSplatParams[0]['ProgramName'])'"
        TestSeriesSplatParams   = $TestSplatParams[0]
        TestSeriesFunctionNames = @("CommonTestSeries")
    }
    [pscustomobject]@{
        TestSeriesName          = "ProgramName and ResolveCommandPath"
        TestSeriesDescription   = "Test output using: $ProgramAndCmdNameString"
        TestSeriesSplatParams   = $TestSplatParams[1]
        TestSeriesFunctionNames = @("CommonTestSeries")
    }
    [pscustomobject]@{
        TestSeriesName          = "ProgramName and CommandName"
        TestSeriesDescription   = "Test output using: $ProgramAndCmdNameString"
        TestSeriesSplatParams   = $TestSplatParams[2]
        TestSeriesFunctionNames = @("CommonTestSeries")
    }
    [pscustomobject]@{
        TestSeriesName          = "ProgramName and CommandName and ScanCDriveForMainExeIfNecessary"
        TestSeriesDescription   = "Test output using: $ProgramAndCmdNameString"
        TestSeriesSplatParams   = $TestSplatParams[3]
        TestSeriesFunctionNames = @("CommonTestSeries")
    }
    [pscustomobject]@{
        TestSeriesName          = "ProgramName and CommandName and PreRelease"
        TestSeriesDescription   = "Test output using: $ProgramAndCmdNameString -PreRelease"
        TestSeriesSplatParams   = $TestSplatParams[4]
        TestSeriesFunctionNames = @("CommonTestSeries")
    }
    [pscustomobject]@{
        TestSeriesName          = "ProgramName and CommandName and ResolveCommandPath is False"
        TestSeriesDescription   = "Test output using: $ProgramAndCmdNameString -ResolveCommandPath:`$False"
        TestSeriesSplatParams   = $TestSplatParams[5]
        TestSeriesFunctionNames = @("CommonTestSeries")
    }
    [pscustomobject]@{
        TestSeriesName          = "ProgramName and CommandName and ExpectedInstallLocation"
        TestSeriesDescription   = "Test output using: $ProgramAndCmdNameString -ExpectedInstallLocation 'C:\Program Files\OpenSSH-Win64'"
        TestSeriesSplatParams   = $TestSplatParams[6]
        TestSeriesFunctionNames = @("CommonTestSeries")
    }
    [pscustomobject]@{
        TestSeriesName          = "ProgramName and CommandName and PowerShellGet"
        TestSeriesDescription   = "Test output using: $ProgramAndCmdNameString -UserPowerShellGet"
        TestSeriesSplatParams   = $TestSplatParams[7]
        TestSeriesFunctionNames = @("CommonTestSeries")
    }
    [pscustomobject]@{
        TestSeriesName          = "ProgramName and CommandName and PowerShellGet and ForceChocolateyInstallScript"
        TestSeriesDescription   = "Test output using: $ProgramAndCmdNameString -UserPowerShellGet -ForceChocoInstallScript"
        TestSeriesSplatParams   = $TestSplatParams[8]
        TestSeriesFunctionNames = @("CommonTestSeries")
    }
    [pscustomobject]@{
        TestSeriesName          = "ProgramName and CommandName and PowerShellGet and UseChocolateyCmdLine"
        TestSeriesDescription   = "Test output using: $ProgramAndCmdNameString -UseChocolateyCmdLine"
        TestSeriesSplatParams   = $TestSplatParams[9]
        TestSeriesFunctionNames = @("CommonTestSeries")
    }
)

$global:MockResources = @{
    Functions           = $Functions
    SplatParamsSeries   = $SplatParamsSeries
    FakeOutputHT        = $FakeOutputHT
}

InModuleScope ProgramManagement {
    Describe "Test Install-Program" {
        Context "Non-Elevated PowerShell Session" {
            # IMPORTANT NOTE: Any functions that you'd like the 'it' blocks to use should be written in the 'Context' scope HERE!
            $global:MockResources['Functions'] | foreach { Invoke-Expression $_ }

            Mock 'GetElevation' -MockWith {$False}

            It "Should Throw An Error" {
                # New-SudoSession Common Parameters
                $IPSplat = @{
                    ProgramName = "openssh"
                    OutVariable = "InstallProgramResult"
                }

                {Install-Program @IPSplat} | Assert-Throw
            }
        }

        $i = 0
        foreach ($Series in $global:MockResources['SplatParamsSeries']) {
            $ContextSBPrep = @(
                "`$ContextInfo = `$global:MockResources['SplatParamsSeries'][$i].TestSeriesName"
                '$global:ContextStringBuilder = "Elevated PowerShell Session w/ $ContextInfo"'
                'Context $global:ContextStringBuilder {'
                '    $global:MockResources["Functions"] | foreach { Invoke-Expression $_ }'
                '    Mock "GetElevation" -MockWith {$True}'
                "    StartTesting -SplatParamsSeriesItem `$global:MockResources['SplatParamsSeries'][$i] -ContextString `$global:ContextStringBuilder"
                '}'
            )
            $ContextSB = [scriptblock]::Create($($ContextSBPrep -join "`n"))
            $ContextSB.InvokeReturnAsIs()
            $i++
        }
    }
}
#>

# SIG # Begin signature block
# MIIMaAYJKoZIhvcNAQcCoIIMWTCCDFUCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUdSJpS/zOzwyNWgeCwpf20cFx
# boSgggndMIIEJjCCAw6gAwIBAgITawAAAERR8umMlu6FZAAAAAAARDANBgkqhkiG
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
# BDEWBBSvD8GZDeLQJ7RrNFdoszu/ua8BQzANBgkqhkiG9w0BAQEFAASCAQBPTAib
# h7Xd/0UcJs+vJ2p/FI3bCN3Y+VkReKs2saJjaPbQwBpcC7UtAK8gG9m5ktSZQMNR
# J7ee1BzNE5KekFUXtVzepYz2Wjrj4rqB27ylzMn5159LQtGvm/e9c4+q9grzgoy9
# KjxJekrl2wUiIbMdccThs6geGbPGDwe48psqwUHIQCHL5gPtdD2lgRrAH1VyoGOD
# pcIPoGK1+l/Z7+baa3QsSI6cy+zDONvVNrO8ubysm6gYBAhxsTRaIDKGCN8UvF+6
# mI42x5FCaQbtWWIeJ/DgiJi1XVix22XCHjkmoo+DtiU+FY7kEl+jSID37//6nbA/
# pLpcbfeCSlYteM5k
# SIG # End signature block
