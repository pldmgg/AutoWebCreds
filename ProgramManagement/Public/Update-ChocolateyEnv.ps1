<#
    .SYNOPSIS
        This function updates $env:Path to include directories that contain programs installed via the Chocolatey
        Package Repository / Chocolatey CmdLine. It also loads Chocolatey PowerShell Modules required for package
        installation via a Chocolatey Package's 'chocoinstallscript.ps1'.

        NOTE: This function will remove paths in $env:Path that do not exist on teh filesystem.

    .DESCRIPTION
        See .SYNOPSIS

    .NOTES

    .PARAMETER ChocolateyDirectory
        This parameter is OPTIONAL.

        This parameter takes a string that represents the path to the location of the Chocolatey directory on your filesystem.
        Use this parameter ONLY IF Chocolatey packages are NOT located under "C:\Chocolatey" or "C:\ProgramData\chocolatey". 

    .PARAMETER UninstallAllSimilarlyNamedPackages
        This parameter is OPTIONAL.

        This parameter is a switch. If used, all programs that match the string provided to the -ProgramName
        parameter will be uninstalled. The user will NOT receive a prompt for specific selection.

    .EXAMPLE
        # Open an elevated PowerShell Session, import the module, and -
        
        PS C:\Users\zeroadmin> Update-ChocolateyEnv

#>
function Update-ChocolateyEnv {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$False)]
        [string]$ChocolateyDirectory
    )

    ##### BEGIN Main Body #####

    $ChocoRoot = "C:\ProgramData\chocolatey"
    $ChocoPath = $ChocoPath + '\bin'

    if (!$(Test-Path $ChocoPath)) {
        Write-Error "Unable to find path $ChocoPath ! Try running Install-ChocolateyCmdLine. Halting!"
        return
    }

    # Clean up $env:Path
    $CleanEnvPath = $($($($env:Path -split ";") | foreach {
        if (-not [System.String]::IsNullOrWhiteSpace($_)) {
            if (Test-Path $_) {
                $_.Trim("\\")
            }
        }
    }) | Select-Object -Unique) -join ";"
    $env:Path = $CleanEnvPath

    # Make sure C:\ProgramData\chocolatey\bin is part of $env:Path
    $PathArray = $env:Path -split ';'
    if (!$($PathArray -match [regex]::Escape($ChocoPath))) {
        $env:Path = $ChocoPath + ';' + $env:Path
    }

    <#
    # Next, find chocolatey-core.psm1, chocolatey-windowsupdate.psm1, chocolateyInstaller.psm1, and chocolateyProfile.psm1
    # and import them
    $ChocoProfileModulePath = $ChocoRoot + '\helpers\chocolateyProfile.psm1'
    $ChocoInstallerModulePath = $ChocoRoot + '\helpers\chocolateyInstaller.psm1'
    $ChocoCoreModulePath = $ChocoRoot + '\extensions\chocolatey-core\chocolatey-core.psm1'
    $ChocoWinUpdateModulePath = $ChocoRoot + '\extensions\chocolatey-windowsupdate\chocolatey-windowsupdate.psm1'

    $ChocoModulesToImport = @($ChocoProfileModulePath, $ChocoInstallerModulePath, $ChocoCoreModulePath, $ChocoWinUpdateModulePath)

    foreach ($ModulePath in $ChocoModulesToImport) {
        Remove-Module -Name $([System.IO.Path]::GetFileNameWithoutExtension($ModulePath)) -ErrorAction SilentlyContinue
        Import-Module -Name $ModulePath
    }
    #>

    # Make sure we have ChocolateyInstall environment variable are set
    $CurrentChocoEnvVariables = $($([Environment]::GetEnvironmentVariables()).GetEnumerator()) | Where-Object {$_.Name -match "Choco"}

    if (-not @($CurrentChocoEnvVariables.Name) -match "ChocolateyInstall") {
        $env:ChocolateyInstall = "C:\ProgramData\chocolatey"
        $null = [Environment]::SetEnvironmentVariable("ChocolateyInstall", $env:ChocolateyInstall, "User")
        $null = [Environment]::SetEnvironmentVariable("ChocolateyInstall", $env:ChocolateyInstall, "Machine")
    }

    $env:Path

    ##### END Main Body #####

}

# SIG # Begin signature block
# MIIMaAYJKoZIhvcNAQcCoIIMWTCCDFUCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUSLHSqEnmIw24KisJOZJJQ/4X
# DEGgggndMIIEJjCCAw6gAwIBAgITawAAAERR8umMlu6FZAAAAAAARDANBgkqhkiG
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
# BDEWBBTo9gT509/8fq1o/TUY2F6qeGJtIDANBgkqhkiG9w0BAQEFAASCAQDE2swy
# hdYO4OXLMqnmvlUMMM8x9iqzu8wERdnBb+G5/Tw/xUc40ZSeGp+bMT6aCisXVxkb
# 6j2plCIxy1hc47UUkQxKw2z4GOZlwcGK+SC+rfGxlMDYqea4ZOOLYRVMl9MWoFkm
# 0xgsV/s+H0e3TrexOBXNKmruEFMLK1+L2uVFbAiol6SRYLZNfaf+BFr53k1sh3zy
# JZoGw1Tqw0gE7JxoJs3BLkidIUhpRoFiFNKTdl38yxssi6OzD3Qa7kUQXoCmZjgs
# TQe2t8fPHVUkTaXyzGm+sCbaim7Da06FAUq5chUvDVSAG7cJU0zRSE4T5LA8dO9g
# Bv7rlUCXZWT/jhh9
# SIG # End signature block
