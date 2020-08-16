function UnzipFile {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true,Position=0)]
        [string]$PathToZip,
        
        [Parameter(Mandatory=$true,Position=1)]
        [string]$TargetDir,

        [Parameter(Mandatory=$false,Position=2)]
        [string[]]$SpecificItem
    )

    if ($PSVersionTable.PSEdition -eq "Core") {
        [System.Collections.ArrayList]$AssembliesToCheckFor = @("System.Console","System","System.IO",
            "System.IO.Compression","System.IO.Compression.Filesystem","System.IO.Compression.ZipFile"
        )

        [System.Collections.ArrayList]$NeededAssemblies = @()

        foreach ($assembly in $AssembliesToCheckFor) {
            try {
                [System.Collections.ArrayList]$Failures = @()
                try {
                    $TestLoad = [System.Reflection.Assembly]::LoadWithPartialName($assembly)
                    if (!$TestLoad) {
                        throw
                    }
                }
                catch {
                    $null = $Failures.Add("Failed LoadWithPartialName")
                }

                try {
                    $null = Invoke-Expression "[$assembly]"
                }
                catch {
                    $null = $Failures.Add("Failed TabComplete Check")
                }

                if ($Failures.Count -gt 1) {
                    $Failures
                    throw
                }
            }
            catch {
                Write-Host "Downloading $assembly..."
                $NewAssemblyDir = "$HOME\Downloads\$assembly"
                $NewAssemblyDllPath = "$NewAssemblyDir\$assembly.dll"
                if (!$(Test-Path $NewAssemblyDir)) {
                    New-Item -ItemType Directory -Path $NewAssemblyDir
                }
                if (Test-Path "$NewAssemblyDir\$assembly*.zip") {
                    Remove-Item "$NewAssemblyDir\$assembly*.zip" -Force
                }

                $CurrentNugetAPIEndpointsPrep = (Invoke-RestMethod -uri 'https://api.nuget.org/v3/index.json' | Where-Object {$_.version -eq '3.0.0'}).resources
                $CurrentNugetAPIEndpoints = $CurrentNugetAPIEndpointsPrep | Where-Object {$_.'@type' -like '*Registration*'} | Select-Object -Property '@id','@type'
                $RegistrationsBaseUrl = $($CurrentNugetAPIEndpoints | Where-Object {$_.'@type' -eq 'RegistrationsBaseUrl'}).'@id'
                $PackageNameLowercase = $assembly.ToLowerInvariant()
                $RestResult = Invoke-RestMethod -Uri $($RegistrationsBaseUrl + $PackageNameLowercase + '/' + "index.json")
                $LatestVerOfPackage = $($RestResult.items.upper | foreach { try {[version]$_} catch {} } | Sort-Object)[-1].ToString()
                $DLLink = Invoke-RestMethod -Uri $($RegistrationsBaseUrl + $PackageNameLowercase + '/' + $LatestVerOfPackage + '.json').packageContent
                $OutFileBaseNamePrep = $DLLink | Split-Path -Leaf
                $OutFileBaseName = $OutFileBaseNamePrep -replace "nupkg","zip"
                $OutFilePath = "$NewAssemblyDir\$OutFileBaseName"

                [Net.ServicePointManager]::SecurityProtocol = "tls12, tls11, tls"
                [System.Net.WebClient]::new().Downloadfile($DLLink, $OutFilePath)

                #$OutFileBaseNamePrep = Invoke-WebRequest "https://www.nuget.org/api/v2/package/$assembly" -DisableKeepAlive -UseBasicParsing
                #$OutFileBaseName = $($OutFileBaseNamePrep.BaseResponse.ResponseUri.AbsoluteUri -split "/")[-1] -replace "nupkg","zip"
                #Invoke-WebRequest -Uri "https://www.nuget.org/api/v2/package/$assembly" -OutFile "$NewAssemblyDir\$OutFileBaseName"
                
                Expand-Archive -Path $OutFilePath -DestinationPath $NewAssemblyDir

                $PossibleDLLs = Get-ChildItem -Recurse $NewAssemblyDir | Where-Object {$_.Name -eq "$assembly.dll" -and $_.Parent -notmatch "net[0-9]" -and $_.Parent -match "core|standard"}

                if ($PossibleDLLs.Count -gt 1) {
                    Write-Warning "More than one item within $OutFilePath matches $assembly.dll"
                    Write-Host "Matches include the following:"
                    for ($i=0; $i -lt $PossibleDLLs.Count; $i++){
                        "$i) $($($PossibleDLLs[$i]).FullName)"
                    }
                    $Choice = Read-Host -Prompt "Please enter the number corresponding to the .dll you would like to load [0..$($($PossibleDLLs.Count)-1)]"
                    if ($(0..$($($PossibleDLLs.Count)-1)) -notcontains $Choice) {
                        Write-Error "The number indicated does is not a valid choice! Halting!"
                        $global:FunctionResult = "1"
                        return
                    }

                    if ($PSVersionTable.Platform -eq "Win32NT") {
                        # Install to GAC
                        [System.Reflection.Assembly]::LoadWithPartialName("System.EnterpriseServices")
                        $publish = New-Object System.EnterpriseServices.Internal.Publish
                        $publish.GacInstall($PossibleDLLs[$Choice].FullName)
                    }

                    # Copy it to the root of $NewAssemblyDir\$OutFileBaseName
                    Copy-Item -Path "$($PossibleDLLs[$Choice].FullName)" -Destination "$NewAssemblyDir\$assembly.dll"

                    # Remove everything else that was extracted with Expand-Archive
                    Get-ChildItem -Recurse $NewAssemblyDir | Where-Object {
                        $_.FullName -ne "$NewAssemblyDir\$assembly.dll" -and
                        $_.FullName -ne "$NewAssemblyDir\$OutFileBaseName"
                    } | Remove-Item -Recurse -Force
                    
                }
                if ($PossibleDLLs.Count -lt 1) {
                    Write-Error "No matching .dll files were found within $OutFilePath ! Halting!"
                    continue
                }
                if ($PossibleDLLs.Count -eq 1) {
                    if ($PSVersionTable.Platform -eq "Win32NT") {
                        # Install to GAC
                        [System.Reflection.Assembly]::LoadWithPartialName("System.EnterpriseServices")
                        $publish = New-Object System.EnterpriseServices.Internal.Publish
                        $publish.GacInstall($PossibleDLLs.FullName)
                    }

                    # Copy it to the root of $NewAssemblyDir\$OutFileBaseName
                    Copy-Item -Path "$($PossibleDLLs[$Choice].FullName)" -Destination "$NewAssemblyDir\$assembly.dll"

                    # Remove everything else that was extracted with Expand-Archive
                    Get-ChildItem -Recurse $NewAssemblyDir | Where-Object {
                        $_.FullName -ne "$NewAssemblyDir\$assembly.dll" -and
                        $_.FullName -ne $OutFilePath
                    } | Remove-Item -Recurse -Force
                }
            }
            $AssemblyFullInfo = [System.Reflection.Assembly]::LoadWithPartialName($assembly)
            if (!$AssemblyFullInfo) {
                $AssemblyFullInfo = [System.Reflection.Assembly]::LoadFile("$NewAssemblyDir\$assembly.dll")
            }
            if (!$AssemblyFullInfo) {
                Write-Error "The assembly $assembly could not be found or otherwise loaded! Halting!"
                $global:FunctionResult = "1"
                return
            }
            $null = $NeededAssemblies.Add([pscustomobject]@{
                AssemblyName = "$assembly"
                Available = if ($AssemblyFullInfo){$true} else {$false}
                AssemblyInfo = $AssemblyFullInfo
                AssemblyLocation = $AssemblyFullInfo.Location
            })
        }

        if ($NeededAssemblies.Available -contains $false) {
            $AssembliesNotFound = $($NeededAssemblies | Where-Object {$_.Available -eq $false}).AssemblyName
            Write-Error "The following assemblies cannot be found:`n$AssembliesNotFound`nHalting!"
            $global:FunctionResult = "1"
            return
        }

        $Assem = $NeededAssemblies.AssemblyInfo.FullName

        $Source = @"
        using System;
        using System.IO;
        using System.IO.Compression;

        namespace MyCore.Utils
        {
            public static class Zip
            {
                public static void ExtractAll(string sourcepath, string destpath)
                {
                    string zipPath = @sourcepath;
                    string extractPath = @destpath;

                    using (ZipArchive archive = ZipFile.Open(zipPath, ZipArchiveMode.Update))
                    {
                        archive.ExtractToDirectory(extractPath);
                    }
                }

                public static void ExtractSpecific(string sourcepath, string destpath, string specificitem)
                {
                    string zipPath = @sourcepath;
                    string extractPath = @destpath;
                    string itemout = @specificitem.Replace(@"\","/");

                    //Console.WriteLine(itemout);

                    using (ZipArchive archive = ZipFile.OpenRead(zipPath))
                    {
                        foreach (ZipArchiveEntry entry in archive.Entries)
                        {
                            //Console.WriteLine(entry.FullName);
                            //bool satisfied = new bool();
                            //satisfied = entry.FullName.IndexOf(@itemout, 0, StringComparison.CurrentCultureIgnoreCase) != -1;
                            //Console.WriteLine(satisfied);

                            if (entry.FullName.IndexOf(@itemout, 0, StringComparison.CurrentCultureIgnoreCase) != -1)
                            {
                                string finaloutputpath = extractPath + "\\" + entry.Name;
                                entry.ExtractToFile(finaloutputpath, true);
                            }
                        }
                    } 
                }
            }
        }
"@

        $CurrentLoadedAssemblies = [System.AppDomain]::CurrentDomain.GetAssemblies()
        $CheckMyCoreUtilsDownloadIdLoaded = $CurrentLoadedAssemblies | Where-Object {$_.ExportedTypes -like "MyCore.Utils.Zip*"}
        if ($CheckMyCoreUtilsDownloadIdLoaded -eq $null) {
            Add-Type -ReferencedAssemblies $Assem -TypeDefinition $Source
        }
        else {
            Write-Warning "The Namespace MyCore.Utils Class Zip is already loaded!"
        }
        
        if (!$SpecificItem) {
            [MyCore.Utils.Zip]::ExtractAll($PathToZip, $TargetDir)
        }
        else {
            [MyCore.Utils.Zip]::ExtractSpecific($PathToZip, $TargetDir, $SpecificItem)
        }
    }


    if ($PSVersionTable.PSEdition -eq "Desktop" -and $($($PSVersionTable.Platform -and $PSVersionTable.Platform -eq "Win32NT") -or !$PSVersionTable.Platform)) {
        <#
        if ($SpecificItem) {
            foreach ($item in $SpecificItem) {
                if ($SpecificItem -match "\\") {
                    $SpecificItem = $SpecificItem -replace "\\","\\"
                }
            }
        }
        #>

        ##### BEGIN Native Helper Functions #####
        function Get-ZipChildItems {
            [CmdletBinding()]
            Param(
                [Parameter(Mandatory=$false,Position=0)]
                [string]$ZipFile = $(Read-Host -Prompt "Please enter the full path to the zip file")
            )

            $shellapp = new-object -com shell.application
            $zipFileComObj = $shellapp.Namespace($ZipFile)
            $i = $zipFileComObj.Items()
            Get-ZipChildItems_Recurse $i
        }

        function Get-ZipChildItems_Recurse {
            [CmdletBinding()]
            Param(
                [Parameter(Mandatory=$true,Position=0)]
                $items
            )

            foreach($si in $items) {
                if($si.getfolder -ne $null) {
                    # Loop through subfolders 
                    Get-ZipChildItems_Recurse $si.getfolder.items()
                }
                # Spit out the object
                $si
            }
        }

        ##### END Native Helper Functions #####

        ##### BEGIN Variable/Parameter Transforms and PreRun Prep #####
        if (!$(Test-Path $PathToZip)) {
            Write-Verbose "The path $PathToZip was not found! Halting!"
            Write-Error "The path $PathToZip was not found! Halting!"
            $global:FunctionResult = "1"
            return
        }
        if ($(Get-ChildItem $PathToZip).Extension -ne ".zip") {
            Write-Verbose "The file specified by the -PathToZip parameter does not have a .zip file extension! Halting!"
            Write-Error "The file specified by the -PathToZip parameter does not have a .zip file extension! Halting!"
            $global:FunctionResult = "1"
            return
        }

        $ZipFileNameWExt = $(Get-ChildItem $PathToZip).Name

        ##### END Variable/Parameter Transforms and PreRun Prep #####

        ##### BEGIN Main Body #####

        Write-Verbose "NOTE: PowerShell 5.0 uses Expand-Archive cmdlet to unzip files"

        if (!$SpecificItem) {
            if ($PSVersionTable.PSVersion.Major -ge 5) {
                Expand-Archive -Path $PathToZip -DestinationPath $TargetDir
            }
            if ($PSVersionTable.PSVersion.Major -lt 5) {
                # Load System.IO.Compression.Filesystem 
                [System.Reflection.Assembly]::LoadWithPartialName("System.IO.Compression.FileSystem") | Out-Null

                # Unzip file
                [System.IO.Compression.ZipFile]::ExtractToDirectory($PathToZip, $TargetDir)
            }
        }
        if ($SpecificItem) {
            $ZipSubItems = Get-ZipChildItems -ZipFile $PathToZip

            foreach ($searchitem in $SpecificItem) {
                [array]$potentialItems = foreach ($item in $ZipSubItems) {
                    if ($item.Path -match $searchitem) {
                        $item
                    }
                }

                $shell = new-object -com shell.application

                if ($potentialItems.Count -eq 1) {
                    $shell.Namespace($TargetDir).CopyHere($potentialItems[0], 0x14)
                }
                if ($potentialItems.Count -gt 1) {
                    Write-Warning "More than one item within $ZipFileNameWExt matches $searchitem."
                    Write-Host "Matches include the following:"
                    for ($i=0; $i -lt $potentialItems.Count; $i++){
                        "$i) $($($potentialItems[$i]).Path)"
                    }
                    $Choice = Read-Host -Prompt "Please enter the number corresponding to the item you would like to extract [0..$($($potentialItems.Count)-1)]"
                    if ($(0..$($($potentialItems.Count)-1)) -notcontains $Choice) {
                        Write-Warning "The number indicated does is not a valid choice! Skipping $searchitem..."
                        continue
                    }
                    for ($i=0; $i -lt $potentialItems.Count; $i++){
                        $shell.Namespace($TargetDir).CopyHere($potentialItems[$Choice], 0x14)
                    }
                }
                if ($potentialItems.Count -lt 1) {
                    Write-Warning "No items within $ZipFileNameWExt match $searchitem! Skipping..."
                    continue
                }
            }
        }
        ##### END Main Body #####
    }
}

# SIG # Begin signature block
# MIIMaAYJKoZIhvcNAQcCoIIMWTCCDFUCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQU2gqn/F6CDDVhDTrIuaXmRmXs
# t36gggndMIIEJjCCAw6gAwIBAgITawAAAERR8umMlu6FZAAAAAAARDANBgkqhkiG
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
# BDEWBBSmLXjBy+sM0oV0nNQ+lSePo2x47TANBgkqhkiG9w0BAQEFAASCAQCGY+FK
# mQMbtcWdwYhaO8VXhHkPVfcpi1bJVQC9srMnpiQ/JczHMz399bAAGKNUQwHdqbcw
# 7Y/oNn5cBO/dkbLAkTE+9mLjuPFlc8qSoRhWMv1plMVVW+q91a8V5yNlQqD5NMHN
# M9W0s1lCW9MyeJc6pQe/ovZRmxFfngiklV4Q0k1DEuzBBaEKP/Iy3WkOmicDBswp
# nGa6SFlVHn1BxVaRAw/xSMkisPeG2Vp4+MpNoX7mA2bEpoVFtJN2ZGR4Vw78mngK
# JktnbKu/eAGt7Is7RmG3MC43rL67RyKW4D71YsPGSGsratT2h7Ozypp9ofoDC7kA
# 78/2da3N4JrRsS7X
# SIG # End signature block
