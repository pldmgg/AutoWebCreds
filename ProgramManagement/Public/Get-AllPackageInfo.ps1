<#
    .SYNOPSIS
        This function gathers information about a particular installed program from 3-4 different sources:
            - The Get-Package Cmdlet fromPowerShellGet/PackageManagement Modules
            - Chocolatey CmdLine (if it is installed)
            - Windows Registry
            - The `Get-AppxPakcage` cmdlet (if the -IncludeAppx switch is used)

        All of this information is needed in order to determine the proper way to install/uninstall a program.

    .DESCRIPTION
        See .SYNOPSIS

    .NOTES

    .PARAMETER ProgramName
        This parameter is OPTIONAL.

        This parameter takes a string that represents the name of the Program that you would like to gather information about.
        The name of the program does NOT have to be exact. For example, if you have 'python3' installed, you can simply use:
            Get-AllAvailablePackages python

    .PARAMETER IncludeAppx
        This parameter is OPTIONAL.

        This parameter is a switch. If used, information about available Appx (UWP) packages will also be returned.

    .EXAMPLE
        # Open an elevated PowerShell Session, import the module, and -
        
        PS C:\Users\zeroadmin> Get-AllPackageInfo -IncludeAppX

    .EXAMPLE
        # Open an elevated PowerShell Session, import the module, and -
        
        PS C:\Users\zeroadmin> Get-AllPackageInfo openssh
#>
function Get-AllPackageInfo {
    [CmdletBinding()]
    Param (
        [Parameter(
            Mandatory=$False,
            Position=0
        )]
        [string]$ProgramName,

        [Parameter(Mandatory=$False)]
        [switch]$IncludeAppx
    )

    if ($ProgramName) {
        # Generate regex string to loosely match Program Name
        $PNRegexPrep = $([char[]]$ProgramName | foreach {"([\.]|[$_])+"}) -join ""
        $PNRegexPrep2 = $($PNRegexPrep -split "\+")[1..$($($PNRegexPrep -split "\+").Count)] -join "+"
        $PNRegex = "$([char[]]$ProgramName[0])+$PNRegexPrep2"
        # For example, $PNRegex string for $ProgramName 'nodejs' should be:
        #     ^n+([\.]|[o])+([\.]|[d])+([\.]|[e])+([\.]|[j])+([\.]|[s])+
    }

    #region >> Check PackageManagement/PowerShellGet for installed Programs

    # If PackageManagement/PowerShellGet is installed, determine if $ProgramName is installed
    if ([bool]$(Get-Command Get-Package -ErrorAction SilentlyContinue)) {
        $PSGetInstalledPrograms = Get-Package

        if ($ProgramName) {
            $PSGetInstalledPackageObjectsFinal = $PSGetInstalledPrograms | Where-Object {$_.Name -match $PNRegex}
        }
        else {
            $PSGetInstalledPackageObjectsFinal = $PSGetInstalledPrograms
        }
    }

    #endregion >> Check PackageManagement/PowerShellGet for installed Programs


    #region >> Check the Registry for installed Programs
    
    # Add some more information regarding these packages - specifically MSIFileItem, MSILastWriteTime, and RegLastWriteTime
    # This info will come in handy if there's a specific order related packages needed to be uninstalled in so that it's clean.
    # (In other words, with this info, we can sort by when specific packages were installed, and uninstall latest to earliest
    # so that there aren't any race conditions)
    try {
        [array]$CheckInstalledPrograms = @(Get-InstalledProgramsFromRegistry -ErrorAction Stop)
    }
    catch {
        Write-Error $_
        return
    }

    $WindowsInstallerMSIs = Get-ChildItem -Path "C:\Windows\Installer" -File
    $RelevantMSIFiles = foreach ($FileItem in $WindowsInstallerMSIs) {
        $MSIProductName = GetMSIFileInfo -MsiFileItem $FileItem -Property ProductName -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
        if ($MSIProductName -match $PNRegex) {
            [pscustomobject]@{
                ProductName = $MSIProductName
                FileItem    = $FileItem
            }
        }
    }
    
    if ($CheckInstalledPrograms.Count -gt 0) {
        if ($($(Get-Item $CheckInstalledPrograms[0].PSPath) | Get-Member).Name -notcontains "LastWriteTime") {
            AddLastWriteTimeToRegKeys
        }

        foreach ($RegPropertiesCollection in $CheckInstalledPrograms) {
            $RegPropertiesCollection | Add-Member -MemberType NoteProperty -Name "LastWriteTime" -Value $(Get-Item $RegPropertiesCollection.PSPath).LastWriteTime
        }
        [System.Collections.ArrayList]$CheckInstalledPrograms = [System.Collections.ArrayList][array]$($CheckInstalledPrograms | Sort-Object -Property LastWriteTime)
        # Make sure that the LATEST Registry change comes FIRST in the ArrayList
        $CheckInstalledPrograms.Reverse()

        foreach ($Package in $PSGetInstalledPackageObjectsFinal) {
            $RelevantMSIFile = $RelevantMSIFiles | Where-Object {$_.ProductName -eq $Package.Name}
            if ($RelevantMSIFile) {
                $Package | Add-Member -MemberType NoteProperty -Name "MSIFileItem" -Value $RelevantMSIFile.FileItem
                $Package | Add-Member -MemberType NoteProperty -Name "MSILastWriteTime" -Value $RelevantMSIFile.FileItem.LastWriteTime
            }

            if ($Package.TagId -ne $null) {
                $RegProperties = $CheckInstalledPrograms | Where-Object {$_.PSChildName -match $Package.TagId}
                $LastWriteTime = $(Get-Item $RegProperties.PSPath).LastWriteTime
                $Package | Add-Member -MemberType NoteProperty -Name "RegLastWriteTime" -Value $LastWriteTime
            }
        }
        [System.Collections.ArrayList]$PSGetInstalledPackageObjectsFinal = [array]$($PSGetInstalledPackageObjectsFinal | Sort-Object -Property MSILastWriteTime)
        # Make sure that the LATEST install comes FIRST in the ArrayList
        $PSGetInstalledPackageObjectsFinal.Reverse()
    }

    if ($ProgramName) {
        $CheckInstalledProgramsFinal = $CheckInstalledPrograms | Where-Object {
            $_.InstallSource -match $PNRegex -or
            $_.DisplayName -match $PNRegex -or
            $_.InstallLocation -eq $PNRegex
        }
    }
    else {
        $CheckInstalledProgramsFinal = $CheckInstalledPrograms
    }

    #endregion >> Check the Registry for installed Programs


    #region >> Check chocolatey for installed Programs

    # If the Chocolatey CmdLine is installed, get a list of programs installed via Chocolatey
    if ([bool]$(Get-Command choco -ErrorAction SilentlyContinue)) {
        #$ChocolateyInstalledProgramsPrep = clist --local-only
        
        $ProcessInfo = New-Object System.Diagnostics.ProcessStartInfo
        #$ProcessInfo.WorkingDirectory = $BinaryPath | Split-Path -Parent
        $ProcessInfo.FileName = $(Get-Command clist).Source
        $ProcessInfo.RedirectStandardError = $true
        $ProcessInfo.RedirectStandardOutput = $true
        $ProcessInfo.UseShellExecute = $false
        $ProcessInfo.Arguments = "--local-only"
        $Process = New-Object System.Diagnostics.Process
        $Process.StartInfo = $ProcessInfo
        $Process.Start() | Out-Null
        # Below $FinishedInAlottedTime returns boolean true/false
        $FinishedInAlottedTime = $Process.WaitForExit(15000)
        if (!$FinishedInAlottedTime) {
            $Process.Kill()
        }
        $stdout = $Process.StandardOutput.ReadToEnd()
        $stderr = $Process.StandardError.ReadToEnd()
        $AllOutput = $stdout + $stderr

        $ChocolateyInstalledProgramsPrep = $($stdout -split "`n")[1..$($($stdout -split "`n").Count-3)]

        [System.Collections.ArrayList]$ChocolateyInstalledProgramObjects = @()

        foreach ($program in $ChocolateyInstalledProgramsPrep) {
            $programParsed = $program -split " "
            $PSCustomObject = [pscustomobject]@{
                ProgramName     = $programParsed[0].Trim()
                Version         = $programParsed[1].Trim()
            }

            $null = $ChocolateyInstalledProgramObjects.Add($PSCustomObject)
        }

        if ($ProgramName) {
            $ChocolateyInstalledProgramObjectsFinal = $ChocolateyInstalledProgramObjects | Where-Object {$_.ProgramName -match $PNRegex}
        }
        else {
            $ChocolateyInstalledProgramObjectsFinal = $ChocolateyInstalledProgramObjects
        }
    }

    #endregion >> Check chocolatey for installed Programs


    #region >> Check for installed Appx Programs

    if ($IncludeAppx) {
        # Get all relevant AppX Package Info
        $AllAppxPackages = Get-AppxPackage -AllUsers
        if ($ProgramName) {
            $AppxPackagesFinal = $AllAppxPackages | Where-Object {$_.Name -match $PNRegex}
        }
        else {
            $AppxPackagesFinal = $AllAppxPackages
        }
        if ($AppxPackagesFinal.Count -gt 0) {
            $AppxPackagesFinal = $AppxPackagesFinal | foreach {
                $AppxManifest = $_.InstallLocation + "\AppxManifest.xml"
                if (Test-Path $AppxManifest) {
                    $AppxManifestContent = Get-Content $AppxManifest
                    $ApplicationIdCheck = $AppxManifestContent -match "Application Id="
                    if ($ApplicationIdCheck) {
                        $AppxId = $($ApplicationIdCheck -split '"')[1].Trim()
                        $LaunchString = 'explorer.exe shell:AppsFolder\'+ $_.PackageFamilyName + '!' + $AppxId
                        $_ | Add-Member -MemberType NoteProperty -Name "LaunchString" -Value $LaunchString
                    }
                    else {
                        $_ | Add-Member -MemberType NoteProperty -Name "LaunchString" -Value "unknown"
                    }
                    $_
                }
            }
        }
    }

    #endregion >> Check for installed Appx Programs

    [pscustomobject]@{
        ChocolateyInstalledProgramObjects           = $ChocolateyInstalledProgramObjectsFinal
        PSGetInstalledPackageObjects                = $PSGetInstalledPackageObjectsFinal
        AppxAvailablePackages                       = $AppxPackagesFinal
        RegistryProperties                          = $CheckInstalledProgramsFinal
    }
}

# SIG # Begin signature block
# MIIMaAYJKoZIhvcNAQcCoIIMWTCCDFUCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUpQoeG+TaRmVzjH9qoXGRGJJo
# AQegggndMIIEJjCCAw6gAwIBAgITawAAAERR8umMlu6FZAAAAAAARDANBgkqhkiG
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
# BDEWBBQzL/GmmS6fDCuPP8rt0BNWG6gKFzANBgkqhkiG9w0BAQEFAASCAQAiu9gX
# 5uxLRC6caoJhScg09bmBHrWgZYHfnbdPk36skye066AFOhgXMnpG4FvoslWqJIGZ
# ETRkajNfNv3My6lF9uaX6Z+f4FLg3J66pnbujcbnIF3/mmSuxILca1GGSNWgcejq
# HT43yzAmQZLtbbTKN2lkSA/bak897ULfUcBEFqTyieG3h1yB3Wlmp2HhTOCWU0uf
# +SShWfB1aQavxdOC5Q2q1y66YyR3cu8IRMi5yeoXJOqCAr5fSxHbf//Tgy5Dhf96
# 4hyRlJok/kAXuj956MjAnFKp05Dn+PQ4ehsvcjFe/SzPpP/pbxRdz5BHeD3AtlMr
# bzdPrpjMEnpvKw9u
# SIG # End signature block
