function New-WebLogin {
    [CmdletBinding()]
    param(
        [parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [ValidateSet("AmazonMusic","Audible","GooglePlay","InternetArchive","NPR","Pandora","ReelGood","Spotify","Tidal","TuneIn","YouTube")]
        [string]$ServiceName,

        [parameter(Mandatory=$false)]
        [string]$ChromeProfileNumber
    )

    $PSCmdString = $ServiceName + 'SeleniumLoginCheck'

    if ($ChromeProfileNumber) {
        $PSCmdString = $PSCmdString + ' ' + '-ChromeProfileNumber' + ' ' + $ChromeProfileNumber
    }

    Invoke-Expression -Command $PSCmdString

}