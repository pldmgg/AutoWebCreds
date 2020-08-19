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

# Verbose output for non-master builds on appveyor
# Handy for troubleshooting.
# Splat @Verbose against commands as needed (here or in pester tests)
$Verbose = @{}
if($env:BHBranchName -notlike "master" -or $env:BHCommitMessage -match "!verbose") {
    $Verbose.add("Verbose",$True)
}

# Make sure the Module is not already loaded
if ([bool]$(Get-Module -Name $env:BHProjectName -ErrorAction SilentlyContinue)) {
    Remove-Module $env:BHProjectName -Force
}

Describe -Name "General Project Validation: $env:BHProjectName" -Tag 'Validation' -Fixture {
    $Scripts = Get-ChildItem $env:BHProjectPath -Include *.ps1,*.psm1,*.psd1 -Recurse

    # TestCases are splatted to the script so we need hashtables
    $TestCasesHashTable = $Scripts | foreach {@{file=$_}}         
    It "Script <file> should be valid powershell" -TestCases $TestCasesHashTable {
        param($file)

        $file.fullname | Should Exist

        $contents = Get-Content -Path $file.fullname -ErrorAction Stop
        $errors = $null
        $null = [System.Management.Automation.PSParser]::Tokenize($contents, [ref]$errors)
        $errors.Count | Should Be 0
    }

    It "Module '$env:BHProjectName' Should Load" -Test {
        {Import-Module $env:BHPSModuleManifest -Force} | Should Not Throw
    }

    It "Module '$env:BHProjectName' Public and Not Private Functions Are Available" {
        $Module = Get-Module $env:BHProjectName
        $Module.Name -eq $env:BHProjectName | Should Be $True
        $Commands = $Module.ExportedCommands.Keys
        $Commands -contains 'AddPath' | Should Be $False
        $Commands -contains 'AmazonAccountLogin' | Should Be $False
        $Commands -contains 'AmazonMusicSeleniumLoginCheck' | Should Be $False
        $Commands -contains 'AmazonMusicUserNamePwdLogin' | Should Be $False
        $Commands -contains 'AppleAccountLogin' | Should Be $False
        $Commands -contains 'AudibleSeleniumLoginCheck' | Should Be $False
        $Commands -contains 'CheckUrlStatus' | Should Be $False
        $Commands -contains 'ChromeDriverAndEventGhostCheck' | Should Be $False
        $Commands -contains 'FacebookAccountLogin' | Should Be $False
        $Commands -contains 'GetAnyBoxPSCreds' | Should Be $False
        $Commands -contains 'GetElevation' | Should Be $False
        $Commands -contains 'GoogleAccountLogin' | Should Be $False
        $Commands -contains 'GooglePlayMusicSeleniumLoginCheck' | Should Be $False
        $Commands -contains 'InstallEventGhost' | Should Be $False
        $Commands -contains 'InternetArchiveSeleniumLoginCheck' | Should Be $False
        $Commands -contains 'InternetArchiveUserNamePwdLogin' | Should Be $False
        $Commands -contains 'NPRSeleniumLoginCheck' | Should Be $False
        $Commands -contains 'NPRUserNamePwdLogin' | Should Be $False
        $Commands -contains 'PandoraSeleniumLoginCheck' | Should Be $False
        $Commands -contains 'PandoraUserNamePwdLogin' | Should Be $False
        $Commands -contains 'ReelGoodSeleniumLoginCheck' | Should Be $False
        $Commands -contains 'ReelGoodUserNamePwdLogin' | Should Be $False
        $Commands -contains 'SeleniumDriverSetup' | Should Be $False
        $Commands -contains 'SetupEventGhost' | Should Be $False
        $Commands -contains 'SpotifySeleniumLoginCheck' | Should Be $False
        $Commands -contains 'SpotifyUserNamePwdLogin' | Should Be $False
        $Commands -contains 'TidalSeleniumLoginCheck' | Should Be $False
        $Commands -contains 'TidalUserNamePwdLogin' | Should Be $False
        $Commands -contains 'TuneInSeleniumLoginCheck' | Should Be $False
        $Commands -contains 'TuneInUserNamePwdLogin' | Should Be $False
        $Commands -contains 'TwitterAccountLogin' | Should Be $False
        $Commands -contains 'UpdateSystemPathNow' | Should Be $False
        $Commands -contains 'UWPCredPrompt' | Should Be $False
        $Commands -contains 'YouTubeSeleniumLoginCheck' | Should Be $False
        $Commands -contains 'YouTubeMusicSeleniumLoginCheck' | Should Be $False
        $Commands -contains 'New-WebLogin' | Should Be $True
    }

    It "Module '$env:BHProjectName' Private Functions Are Available in Internal Scope" {
        $Module = Get-Module $env:BHProjectName
        [bool]$Module.Invoke({Get-Item function:AddPath}) | Should Be $True
        [bool]$Module.Invoke({Get-Item function:AmazonMusicSeleniumLoginCheck}) | Should Be $True
        [bool]$Module.Invoke({Get-Item function:AmazonMusicUserNamePwdLogin}) | Should Be $True
        [bool]$Module.Invoke({Get-Item function:AppleAccountLogin}) | Should Be $True
        [bool]$Module.Invoke({Get-Item function:AudibleSeleniumLoginCheck}) | Should Be $True
        [bool]$Module.Invoke({Get-Item function:CheckUrlStatus}) | Should Be $True
        [bool]$Module.Invoke({Get-Item function:ChromeDriverAndEventGhostCheck}) | Should Be $True
        [bool]$Module.Invoke({Get-Item function:FacebookAccountLogin}) | Should Be $True
        [bool]$Module.Invoke({Get-Item function:GetAnyBoxPSCreds}) | Should Be $True
        [bool]$Module.Invoke({Get-Item function:GetElevation}) | Should Be $True
        [bool]$Module.Invoke({Get-Item function:GoogleAccountLogin}) | Should Be $True
        [bool]$Module.Invoke({Get-Item function:GooglePlayMusicSeleniumLoginCheck}) | Should Be $True
        [bool]$Module.Invoke({Get-Item function:InstallEventGhost}) | Should Be $True
        [bool]$Module.Invoke({Get-Item function:InternetArchiveSeleniumLoginCheck}) | Should Be $True
        [bool]$Module.Invoke({Get-Item function:InternetArchiveUserNamePwdLogin}) | Should Be $True
        [bool]$Module.Invoke({Get-Item function:NPRSeleniumLoginCheck}) | Should Be $True
        [bool]$Module.Invoke({Get-Item function:NPRUserNamePwdLogin}) | Should Be $True
        [bool]$Module.Invoke({Get-Item function:PandoraSeleniumLoginCheck}) | Should Be $True
        [bool]$Module.Invoke({Get-Item function:PandoraUserNamePwdLogin}) | Should Be $True
        [bool]$Module.Invoke({Get-Item function:ReelGoodSeleniumLoginCheck}) | Should Be $True
        [bool]$Module.Invoke({Get-Item function:ReelGoodUserNamePwdLogin}) | Should Be $True
        [bool]$Module.Invoke({Get-Item function:SeleniumDriverSetup}) | Should Be $True
        [bool]$Module.Invoke({Get-Item function:SetupEventGhost}) | Should Be $True
        [bool]$Module.Invoke({Get-Item function:SpotifySeleniumLoginCheck}) | Should Be $True
        [bool]$Module.Invoke({Get-Item function:SpotifyUserNamePwdLogin}) | Should Be $True
        [bool]$Module.Invoke({Get-Item function:TidalSeleniumLoginCheck}) | Should Be $True
        [bool]$Module.Invoke({Get-Item function:TidalUserNamePwdLogin}) | Should Be $True
        [bool]$Module.Invoke({Get-Item function:TuneInSeleniumLoginCheck}) | Should Be $True
        [bool]$Module.Invoke({Get-Item function:TuneInUserNamePwdLogin}) | Should Be $True
        [bool]$Module.Invoke({Get-Item function:TwitterAccountLogin}) | Should Be $True
        [bool]$Module.Invoke({Get-Item function:UpdateSystemPathNow}) | Should Be $True
        [bool]$Module.Invoke({Get-Item function:UWPCredPrompt}) | Should Be $True
        [bool]$Module.Invoke({Get-Item function:YouTubeSeleniumLoginCheck}) | Should Be $True
        [bool]$Module.Invoke({Get-Item function:YouTubeMusicSeleniumLoginCheck}) | Should Be $True
    }
}

# SIG # Begin signature block
# MIIMaAYJKoZIhvcNAQcCoIIMWTCCDFUCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUty3Q1fzELpInmuzS2gSu3iBV
# d3WgggndMIIEJjCCAw6gAwIBAgITawAAAERR8umMlu6FZAAAAAAARDANBgkqhkiG
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
# BDEWBBRaKIM38oZqUu45AA5aMK0c1kmKtzANBgkqhkiG9w0BAQEFAASCAQBiQtiS
# 4+DP/RGvMvvgWdp4S3IYJMrMSmJFs8TKrdU0lFJzHdfqHbPHCxiq2JdPf6fgnH7j
# Xp8LQKmIns1x462ABkPQweZV6w9RfxOOBqSHr07+yOSsxPo1xIpIYxeRuSgs6lmf
# RbHqJdup9OnrP3y673qPoaTeOmjxNhuG4G8quURIH6iczSSQdKQdSuDeVRmc1jHJ
# ThhMjzv/jg+QDPxmV0XbYdjmiY2rknLDhkQAe1gVLMioROfB5EXnd4ycI2Cjd4FJ
# 3HWsQez8lAqfNiSBfIi/E6HUZrVzK+Uxex2LAtwTQjoUcdbp5WYuZGrtO289Muws
# GmZryABpxe/7h/yY
# SIG # End signature block
