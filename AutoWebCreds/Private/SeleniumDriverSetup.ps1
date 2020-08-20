function SeleniumDriverSetup {
    [CmdletBinding()]
    Param ()

    # NOTE: This script works on both Windows and Linux

    $DirSep = [System.IO.Path]::DirectorySeparatorChar

    if (!$(GetElevation)) {
        Write-Error "The $($PSCommandPath | Split-Path -Leaf) script should be run as root! Halting!"
        return
    }

    # Make sure $PSUserPath is part of PATH
    if ($PSVersionTable.Platform -eq "Unix" -or $PSVersionTable.OS -match "Darwin") {
        #$PSUserPath = '/home/ttadmin/.local/share/powershell'
        $PSUserPath = $DirSep + 'home' + $DirSep + 'ttadmin' + $DirSep + '.local' + $DirSep + 'share' + $DirSep + 'powershell'
        $BashrcPath = $HOME + $DirSep + '.bashrc'

        $PathCheckforProfile = @"
[[ ":`$PATH:" != *":$PSUserPath`:"* ]] && PATH="$PSUserPath`:`${PATH}"
"@
        $ProfileContent = Get-Content $BashrcPath
        if (!$($ProfileContent -match $PSUserPath)) {
            Add-Content -Path $BashrcPath -Value $PathCheckforProfile
        }
    } else {
        #$PSUserPath = 'C:\Scripts\powershell'
        $PSUserPath = 'C:' + $DirSep + 'Scripts' + $DirSep + 'powershell'
        if (!$(Test-Path $PSUserPath)) {$null = New-Item -ItemType Directory -Path $PSUserPath -Force}
        $null = AddPath -PathToAdd $PSUserPath -UpdateSystemPath
    }

    if ($PSVersionTable.Platform -eq "Unix" -or $PSVersionTable.OS -match "Darwin") {
        $GeckoDriverPath = $PSUserPath + $DirSep + 'geckodriver'
        $ChromeDriverPath = $PSUserPath + $DirSep + 'chromedriver'
    } else {
        $GeckoDriverPath = $PSUserPath + $DirSep + 'geckodriver.exe'
        $ChromeDriverPath = $PSUserPath + $DirSep + 'chromedriver.exe'
    }
    $DownloadsPath = $HOME + $DirSep + 'Downloads'

    if (!$(Test-Path $GeckoDriverPath)) {
        Push-Location $DownloadsPath

        if ($PSVersionTable.Platform -eq "Unix" -or $PSVersionTable.OS -match "Darwin") {
            $GeckoDriverGitHubInfo = $(Invoke-RestMethod -Uri "https://api.github.com/repos/mozilla/geckodriver/releases/latest").assets | Where-Object {$_.name -match "linux64"}
        } else {
            $GeckoDriverGitHubInfo = $(Invoke-RestMethod -Uri "https://api.github.com/repos/mozilla/geckodriver/releases/latest").assets | Where-Object {$_.name -match "win64"}
        }
        
        if (@($GeckoDriverGitHubInfo.name).Count -gt 1) {
            $GeckoDriverTarFile = @($GeckoDriverGitHubInfo.name) -match 'gz$'
            $GeckoDriverTarFile = $GeckoDriverTarFile[0]
        } else {
            $GeckoDriverTarFile = $GeckoDriverGitHubInfo.name
        }

        $OutputFilePath = $DownloadsPath + $DirSep + $GeckoDriverTarFile
        
        if (@($GeckoDriverGitHubInfo.browser_download_url).Count -gt 1) {
            $GeckoDriverUrl = @($GeckoDriverGitHubInfo.browser_download_url) -match 'gz$'
            $GeckoDriverUrl = $GeckoDriverUrl[0]
        } else {
            $GeckoDriverUrl = $GeckoDriverGitHubInfo.browser_download_url
        }
        $WebClient = [System.Net.WebClient]::new()
        $WebClient.Downloadfile($GeckoDriverUrl, $OutputFilePath)
        #Invoke-WebRequest -Uri $GeckoDriverUrl -OutFile $OutputFilePath
        
        if ($PSVersionTable.Platform -eq "Unix" -or $PSVersionTable.OS -match "Darwin") {
            $ExtractedFileName = tar xvzf $OutputFilePath
        } else {
            <#
            # Check if we have 7zip
            if (!$(Get-Command '7za.exe' -ErrorAction SilentlyContinue)) {
                $OutputFileName = $OutputFilePath | Split-Path -Leaf
                $7zaOutputFilePath = $DownloadsPath + $DirSep + '7za.exe'
                $WebClient = [System.Net.WebClient]::new()
                $WebClient.Downloadfile('https://chocolatey.org/7za.exe', $7zaOutputFilePath)
            }

            # The below extracts the contents of a .tar.gz file without any intermediary steps. See:
            # https://stackoverflow.com/questions/1359793/programmatically-extract-tar-gz-in-a-single-step-on-windows-with-7-zip
            $CommandString = "cd $DownloadsPath && 7za.exe x `"$OutputFileName`" -so | 7za.exe x -aoa -si -ttar -o`"$DownloadsPath`""
            & cmd /c $CommandString

            $ExtractedFileName = 'geckodriver'
            #>

            $ExtractedFileName = $(Expand-Archive -Path $OutputFilePath -DestinationPath $DownloadsPath -Force -PassThru).Name
        }

        $null = Move-Item -Path $ExtractedFileName -Destination $GeckoDriverPath
        
        Pop-Location
    }

    if (!$(Test-Path $ChromeDriverPath)) {
        Push-Location $DownloadsPath
        $ChromeDriverInfo = Invoke-RestMethod -Uri "http://chromedriver.storage.googleapis.com"

        if ($PSVersionTable.Platform -eq "Unix" -or $PSVersionTable.OS -match "Darwin") {
            $ChromeDriverUriTail = $($ChromeDriverInfo.ListBucketResult.Contents | Where-Object {$_.Key -match "linux64" -and $_.Key -notmatch "^2"} | Sort-Object -Property LastModified)[-1].Key
        } else {
            $ChromeDriverUriTail = $($ChromeDriverInfo.ListBucketResult.Contents | Where-Object {$_.Key -match "win32" -and $_.Key -notmatch "^2"} | Sort-Object -Property LastModified)[-1].Key
        }

        $OutFileName = $($ChromeDriverUriTail -split '/')[-1]
        $LatestChromeDriverUrl = "http://chromedriver.storage.googleapis.com/$ChromeDriverUriTail"
        $OutputFilePath = $DownloadsPath + $DirSep + $OutFileName
        $WebClient = [System.Net.WebClient]::new()
        $WebClient.Downloadfile($LatestChromeDriverUrl, $OutputFilePath)
        #Invoke-WebRequest -Uri $LatestChromeDriverUrl -OutFile $OutputFilePath
        
        if ($PSVersionTable.Platform -eq "Unix" -or $PSVersionTable.OS -match "Darwin") {
            $ExtractedFileNamePrep = unzip $OutputFilePath -d $DownloadsPath
            $ExtractedFileName = $($ExtractedFileNamePrep -split ' ' | Where-Object {![String]::IsNullOrWhiteSpace($_)})[-1]
        } else {
            $ExtractedFileName = $(Expand-Archive -Path $OutputFilePath -DestinationPath $DownloadsPath -Force -PassThru).Name
        }

        $null = Move-Item -Path $ExtractedFileName -Destination $ChromeDriverPath

        Pop-Location
    }
}

# SIG # Begin signature block
# MIIMaAYJKoZIhvcNAQcCoIIMWTCCDFUCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUj/VJz9JdteBtbtUKOlppjwZZ
# RhOgggndMIIEJjCCAw6gAwIBAgITawAAAERR8umMlu6FZAAAAAAARDANBgkqhkiG
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
# BDEWBBSa6R2OFW/RKB5tOikU7voo874twDANBgkqhkiG9w0BAQEFAASCAQBg6li5
# vLCHN6UsxbGB/jP1fSfWQ00LoqeMlG3ae3ElskFihyApRQXYM5oGZuAzMnxIrFeo
# h5kInuXKJNpXLJPnwU/au/B74HmoFsN3KWOQ0bPLIq3cbsNp5V9ARS7Okg3qDfDH
# uTimUbaya0ZsQpG8xCcnd5qXIxlRFkFnQVeHoA8OBUoSu39fDteW0V0bG3jfc2BJ
# RPntycEtxwiJz4nzbUd7SM395fS2z97qiNppNUs1vtSCZt7i1f2BVK8tyUNjjugE
# Sqzrbs5IAprvH7dVFzI/JSxEB+0B6VfG9aHi/78+zZYbsINhDgEaRT74q6/AX8Ht
# NnG6q/5wrSvrBch8
# SIG # End signature block
