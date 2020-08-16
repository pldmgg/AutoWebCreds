function ManualPSGalleryModuleInstall {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory=$True)]
        [string]$ModuleName,

        [Parameter(Mandatory=$False)]
        [switch]$PreRelease,

        [Parameter(Mandatory=$False)]
        [string]$DownloadDirectory
    )

    if (!$DownloadDirectory) {
        $DownloadDirectory = $(Get-Location).Path
    }

    if (!$(Test-Path $DownloadDirectory)) {
        Write-Error "The path $DownloadDirectory was not found! Halting!"
        $global:FunctionResult = "1"
        return
    }

    # Determine installed PowerShell Core Versions
    $PSCoreDirItems = @(Get-ChildItem -Path "$env:ProgramFiles\Powershell" -Directory | Where-Object {$_.Name -match "[0-9]"})
    $LatestPSCoreDirPath = $($PSCoreDirItems | Sort-Object -Property CreationTime)[-1].FullName
    $PSCoreUserDocsModulePath = "$HOME\Documents\PowerShell\Modules"
    $WinPSUserDocsModulePath = "$HOME\Documents\WindowsPowerShell\Modules"
    $LatestPSCoreSystemPath = "$LatestPSCoreDirPath\Modules"
    $WinPSSystemPath = "$env:ProgramFiles\WindowsPowerShell\Modules"

    $AllPSModulePaths = @(
        $PSCoreUserDocsModulePath
        $WinPSUserDocsModulePath
        $($LatestPSCoreDirPath | Split-Path -Parent)
        $LatestPSCoreSystemPath
        $WinPSSystemPath
        "$env:SystemRoot\system32\WindowsPowerShell\v1.0\Modules"
    )

    # For the Manual Install, we are going to place the Module in either $LatestPSCoreSystemPath or $WinPSSystemPath
    # depending on the version of PowerShell that we are running
    if ($PSVersionTable.PSVersion -gt 5) {
        if (![bool]$($($env:PSModulePath -split ";") -match [regex]::Escape($LatestPSCoreSystemPath))) {
            $env:PSModulePath = "$LatestPSCoreSystemPath;$env:PSModulePath"
        }
        if (!$(Test-Path $LatestPSCoreSystemPath)) {
            $null = New-Item -ItemType Directory $LatestPSCoreSystemPath -Force
        }
    }
    if ($PSVersionTable.PSVersion -le 5) {
        if (![bool]$($($env:PSModulePath -split ";") -match [regex]::Escape($WinPSSystemPath))) {
            $env:PSModulePath = "$WinPSSystemPath;$env:PSModulePath"
        }
        if (!$(Test-Path $WinPSSystemPath)) {
            $null = New-Item -ItemType Directory $WinPSSystemPath -Force
        }
    }

    if ($PreRelease) {
        $searchUrl = "https://www.powershellgallery.com/api/v2/Packages?`$filter=Id eq '$ModuleName'"
    }
    else {
        $searchUrl = "https://www.powershellgallery.com/api/v2/Packages?`$filter=Id eq '$ModuleName' and IsLatestVersion"
    }
    $ModuleInfo = Invoke-RestMethod $searchUrl
    if (!$ModuleInfo -or $ModuleInfo.Count -eq 0) {
        Write-Error "Unable to find Module Named $ModuleName! Halting!"
        $global:FunctionResult = "1"
        return
    }
    if ($PreRelease) {
        if ($ModuleInfo.Count -gt 1) {
            $ModuleInfo = $($ModuleInfo | Sort-Object -Property Updated)[-1]
        }
    }
    
    $OutFilePath = Join-Path $DownloadDirectory $($ModuleInfo.title.'#text' + $ModuleInfo.properties.version + '.zip')
    if (Test-Path $OutFilePath) {Remove-Item $OutFilePath -Force}

    try {
        #Invoke-WebRequest $ModuleInfo.Content.src -OutFile $OutFilePath
        # Download via System.Net.WebClient is a lot faster than Invoke-WebRequest and also doesn't rely on Internet Explorer engine...
        [Net.ServicePointManager]::SecurityProtocol = "tls12, tls11, tls"
        [System.Net.WebClient]::new().Downloadfile($ModuleInfo.Content.src, $OutFilePath)
    }
    catch {
        Write-Error $_
        $global:FunctionResult = "1"
        return
    }
    
    if (Test-Path "$DownloadDirectory\$ModuleName") {Remove-Item "$DownloadDirectory\$ModuleName" -Recurse -Force}
    Expand-Archive $OutFilePath -DestinationPath "$DownloadDirectory\$ModuleName"

    if ($PSVersionTable.PSVersion -gt 5) {
        if ($DownloadDirectory -ne $LatestPSCoreSystemPath) {
            if (Test-Path "$LatestPSCoreSystemPath\$ModuleName") {
                Remove-Item "$LatestPSCoreSystemPath\$ModuleName" -Recurse -Force
            }
            Copy-Item -Path "$DownloadDirectory\$ModuleName" -Recurse -Destination $LatestPSCoreSystemPath

            Remove-Item "$DownloadDirectory\$ModuleName" -Recurse -Force
        }
    }
    if ($PSVersionTable.PSVersion -le 5) {
        if ($DownloadDirectory -ne $WinPSSystemPath) {
            if (Test-Path "$WinPSSystemPath\$ModuleName") {
                Remove-Item "$WinPSSystemPath\$ModuleName" -Recurse -Force
            }
            Copy-Item -Path "$DownloadDirectory\$ModuleName" -Recurse -Destination $WinPSSystemPath

            Remove-Item "$DownloadDirectory\$ModuleName" -Recurse -Force
        }
    }

    #Remove-Item $OutFilePath -Force
}

# SIG # Begin signature block
# MIIMaAYJKoZIhvcNAQcCoIIMWTCCDFUCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUXd6nQlIQln1kIad0U7GJyjJl
# 4zygggndMIIEJjCCAw6gAwIBAgITawAAAERR8umMlu6FZAAAAAAARDANBgkqhkiG
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
# BDEWBBSNueXVpO5/hL6ASg7+WSaw0C47WzANBgkqhkiG9w0BAQEFAASCAQB5HtvX
# O4I3CbdZswy5RPgl8X5FE9OIMSr68sJA5p5qbKUW105WAPWiX7gkAsBDhgxxCo6h
# DH9I1ZxZpVzdrdNLyDj7WOBReLAELA9a/DZ3x4KsokfXkgTcw9sv3GE++ZA3sRKk
# kK5XwD0iGA0ZjDLawxNSUSI5/jhL8OxLlloZ8l3nDza8e6ntAM2aILJkRrl6il9v
# 7LvbKshR2sfX51wG+IMrhNnywOGg2qkWmkDxwI/xOKMq65DZniaEbF+ax0o/efgV
# iI2mfFwqGnkEfprXhUmLkQ4JWAT2j5ABwQBwKVr8Pd1OOavLSdTkZRaPYsTMdHMG
# 9MOegWcUU9L0Z0hG
# SIG # End signature block
