function SeleniumDriverSetup {
    [CmdletBinding()]
    Param ()

    # NOTE: This script works on both Windows and Linux

    $DirSep = [System.IO.Path]::DirectorySeparatorChar

    if (!$(GetElevation)) {
        Write-Error "The $($PSCommandPath | Split-Path -Leaf) script should be run as root! Halting!"
        $global:FunctionResult = "1"
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


