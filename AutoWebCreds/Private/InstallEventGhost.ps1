function InstallEventGhost {
    [CmdletBinding()]
    param()

    $DirSep = [System.IO.Path]::DirectorySeparatorChar

    $IRMResult = Invoke-RestMethod -Method Get  -Uri "https://api.github.com/repos/eventghost/eventghost/releases/latest"
    $DLUrl = $IRMResult.assets.browser_download_url
    $FileName = $IRMResult.assets.name
    $OutputFilePath = $HOME + $DirSep + 'Downloads' + $DirSep + $FileName

    $WebClient = [System.Net.WebClient]::new()
    $WebClient.Downloadfile($DLUrl, $OutputFilePath)

    # Reference: https://silentinstallhq.com/eventghost-silent-install-how-to-guide/
    & $OutputFilePath /VERYSILENT /NORESTART
}