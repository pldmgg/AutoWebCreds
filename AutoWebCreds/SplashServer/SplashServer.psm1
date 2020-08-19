function NewUniqueString {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$False)]
        [string[]]$ArrayOfStrings,

        [Parameter(Mandatory=$True)]
        [string]$PossibleNewUniqueString
    )

    if (!$ArrayOfStrings -or $ArrayOfStrings.Count -eq 0 -or ![bool]$($ArrayOfStrings -match "[\w]")) {
        $PossibleNewUniqueString
    }
    else {
        $OriginalString = $PossibleNewUniqueString
        $Iteration = 1
        while ($ArrayOfStrings -contains $PossibleNewUniqueString) {
            $AppendedValue = "_$Iteration"
            $PossibleNewUniqueString = $OriginalString + $AppendedValue
            $Iteration++
        }

        $PossibleNewUniqueString
    }
}

function Setup-SplashServer {
    [CmdletBinding()]
    Param ()

    if (!$(Get-Command apt -ErrorAction SilentlyContinue)) {
        Write-Error "The Setup-SplashServer function must be run on Debian or Ubuntu. Halting!"
        return
    }

    if (!$(Get-Command docker -ErrorAction SilentlyContinue)) {
        Write-Error "Please install docker before using the Setup-SplashServer function. Halting!"
        return
    }

    $DotnetSDKCheck = apt list --installed 2>/dev/null | grep dotnet-sdk-3.1
    if (!$DotnetSDKCheck) {
        sudo apt install -y dotnet-sdk-3.1
    }
    $DotnetSDKCheck = apt list --installed 2>/dev/null | grep dotnet-sdk-3.1
    if (!$DotnetSDKCheck) {
        Write-Error "The apt package dotnet-sdk-3.1 is not installed. Halting!"
        return
    }

    docker run -d --restart=always -p 8050:8050 -p 5023:5023 --name=splashserver scrapinghub/splash
    
    try {
        Install-DotNetScript -ErrorAction Stop
    } catch {
        Write-Error $_
        return
    }
}

function Install-DotNetScript {
    [CmdletBinding()]
    Param ()

    if (!$(Get-Command dotnet -ErrorAction SilentlyContinue)) {
        Write-Error "Unable to find the 'dotnet' binary! Halting!"
        $global:FunctionResult = "1"
        return
    }

    dotnet tool install -g dotnet-script

    # $HOME/.dotnet/tools
    $DirSep = [System.IO.Path]::DirectorySeparatorChar
    $DotNetToolsDir = $HOME + $DirSep + '.dotnet' + $DirSep + 'tools'
    $PathSeparatorChar = if ($PSVersionTable.Platform -eq "Unix" -or $PSVersionTable.OS -match "Darwin") {':'} else {';'}

    [System.Collections.Arraylist][array]$CurrentEnvPathArray = $env:PATH -split $PathSeparatorChar | Where-Object {![System.String]::IsNullOrWhiteSpace($_)} | Sort-Object | Get-Unique
    if ($CurrentEnvPathArray -notcontains $DotNetToolsDir) {
        $CurrentEnvPathArray.Insert(0,$DotNetToolsDir)
        $env:PATH = $CurrentEnvPathArray -join $PathSeparatorChar
    }

    if ($PSVersionTable.Platform -eq "Unix" -or $PSVersionTable.OS -match "Darwin") {
        $PathCheckforProfile = @"
[[ ":`$PATH:" != *":$DotNetToolsDir`:"* ]] && PATH="$DotNetToolsDir`:`${PATH}"
"@
        $ProfileContent = Get-Content "$HOME/.profile"
        if (!$($ProfileContent -match 'dotnet/tools')) {
            Add-Content -Path "$HOME/.profile" -Value $PathCheckforProfile
        }
    }

    if (!$(Get-Command dotnet-script -ErrorAction SilentlyContinue)) {
        Write-Error "Something went wrong during installation of 'dotnet-script' via the dotnet cli. Please review the above output. Halting!"
        $global:FunctionResult = "1"
        return
    }
}

function Get-SiteAsJson {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory=$True)]
        [uri]$Url,

        [Parameter(Mandatory=$False)]
        [uri]$SplashServerUri = "http://localhost:8050",

        [Parameter(Mandatory=$False)]
        [string]$XPathJsonConfigString,

        [Parameter(Mandatory=$False)]
        [string]$XPathJsonConfigFile,

        [Parameter(Mandatory=$False)]
        [string]$LuaScript,
        
        [Parameter(Mandatory=$False)]
        [switch]$HandleInfiniteScrolling,

        [Parameter(Mandatory=$False)]
        [string]$NewProjectDirectory,

        [Parameter(Mandatory=$False)]
        [switch]$RemoveFileOutputs
    )

    # Make sure we have dotnet and dotnet-script in our $env:PATH
    $DirSep = [IO.Path]::DirectorySeparatorChar

    if (!$(Get-Command dotnet-script -ErrorAction SilentlyContinue)) {
        $DotNetToolsDir = $HOME + $DirSep + '.dotnet' + $DirSep + 'tools'

        if (!$(Test-Path $DotNetToolsDir)) {
            Write-Error "Unable to find '$DotNetToolsDir'! Halting!"
            $global:FunctionResult = "1"
            return
        }

        [System.Collections.Arraylist][array]$CurrentEnvPathArray = $env:PATH -split ';' | Where-Object {![System.String]::IsNullOrWhiteSpace($_)} | Sort-Object | Get-Unique
        if ($CurrentEnvPathArray -notcontains $DotNetToolsDir) {
            $CurrentEnvPathArray.Insert(0,$DotNetToolsDir)
            $env:PATH = $CurrentEnvPathArray -join ';'
        }
    }
    if (!$(Get-Command dotnet-script -ErrorAction SilentlyContinue)) {
        Write-Error "Unable to find 'dotnet-script' binary! Halting!"
        $global:FunctionResult = "1"
        return
    }

    if (!$PSVersionTable.Platform -or $PSVersionTable.Platform -eq "Win32NT") {
        if (!$(Get-Command dotnet -ErrorAction SilentlyContinue)) {
            $DotNetDir = "C:\Program Files\dotnet"

            if (!$(Test-Path $DotNetDir)) {
                Write-Error "Unable to find '$DotNetDir'! Halting!"
                $global:FunctionResult = "1"
                return
            }

            [System.Collections.Arraylist][array]$CurrentEnvPathArray = $env:PATH -split ';' | Where-Object {![System.String]::IsNullOrWhiteSpace($_)} | Sort-Object | Get-Unique
            if ($CurrentEnvPathArray -notcontains $DotNetDir) {
                $CurrentEnvPathArray.Insert(0,$DotNetDir)
                $env:PATH = $CurrentEnvPathArray -join ';'
            }
        }
        if (!$(Get-Command dotnet -ErrorAction SilentlyContinue)) {
            Write-Error "Unable to find 'dotnet' binary! Halting!"
            $global:FunctionResult = "1"
            return
        }
    }
    if ($PSVersionTable.Platform -eq "Unix" -or $PSVersionTable.OS -match "Darwin") {
        if (!$(Get-Command dotnet -ErrorAction SilentlyContinue)) {
            Write-Error "Unable to find 'dotnet' binary! Halting!"
            $global:FunctionResult = "1"
            return
        }
    }

    if (!$XPathJsonConfigFile -and !$XPathJsonConfigString) {
        Write-Error "The $($MyInvocation.MyCommand.Name) function requires either the -XPathJsonConfigString or the -XPathJsonConfigFile parameter! Halting!"
        $global:FunctionResult = "1"
        return
    }

    if ($HandleInfiniteScrolling -and $LuaScript) {
        Write-Error "Please use *either* the -HandleInfiniteScrolling *or* the -LuaScript parameter. Halting!"
        $global:FunctionResult = "1"
        return
    }

    $UrlString = $Url.OriginalString
    if ($UrlString[-1] -ne '/') {
        $UrlString = $UrlString + '/'
    }

    $SplashServerUriString = $SplashServerUri.OriginalString
    
    $SiteNamePrep = @($($Url.OriginalString -split '/' | Where-Object {$_ -notmatch 'http' -and ![System.String]::IsNullOrWhiteSpace($_)}))[0]
    $SiteNamePrepA = $($SiteNamePrep -split '\.') -split ':'
    $SiteName = @($($SiteNamePrepA | Where-Object {$_ -notmatch 'www' -and ![System.String]::IsNullOrWhiteSpace($_)}))[0]

    if (!$SiteName) {
        Write-Error "Unable to parse site domain name from the value provided to the -Url parameter! Halting!"
        $global:FunctionResult = "1"
        return
    }

    if ($XPathJsonConfigFile) {
        try {
            $XPathJsonConfigFile = $(Resolve-Path $XPathJsonConfigFile -ErrorAction Stop).Path
        }
        catch {
            Write-Error $_
            $global:FunctionResult = "1"
            return
        }

        # Make sure the file is valid Json
        try {
            $JsonContent = Get-Content $XPathJsonConfigFile
            $JsonAsPSObject = $JsonContent | ConvertFrom-Json -ErrorAction Stop
        }
        catch {
            Write-Error $_
            $global:FunctionResult = "1"
            return
        }
    }
    if ($XPathJsonConfigString) {
        # Make sure the string is valid Json
        try {
            $JsonAsPSObject = $XPathJsonConfigString | ConvertFrom-Json -ErrorAction Stop
        }
        catch {
            Write-Error $_
            $global:FunctionResult = "1"
            return
        }
    }

    # Check to see if a Project folder of the same name as $SiteName exists in either the current directory or the Parent Directory of $NewProjectDirectory
    if (!$NewProjectDirectory) {
        $PotentialProjectDirectories = @($(Get-ChildItem -Directory))
        if ($PotentialProjectDirectories.Name -contains $SiteName) {
            $DirItem = $PotentialProjectDirectories | Where-Object {$_.Name -eq $SiteName}
            
            # Make sure the existing project directory actually has a .csproj file in it to confirm it's a real project
            $DirItemContents = Get-ChildItem -Path $DirItem.FullName -File -Filter "*.csproj"
            if ($DirItemContents) {
                $ProjectDirectoryItem = $DirItem
            }
        }
    }
    else {
        $PotentialProjectDirParentDir = $NewProjectDirectory | Split-Path -Parent
        $PotentialProjectDirName = $NewProjectDirectory | Split-Path -Leaf

        $PotentialProjectDirectories = @($(Get-ChildItem -Path $PotentialProjectDirParentDir -Directory).Name)
        if ($PotentialProjectDirectories -contains $PotentialProjectDirName) {
            $DirItem = $PotentialProjectDirectories | Where-Object {$_.Name -eq $PotentialProjectDirName}

            # Make sure the existing project directory actually has a .csproj file in it to confirm it's a real project
            $DirItemContents = Get-ChildItem -Path $DirItem.FullName -File -Filter "*.csproj"
            if ($DirItemContents) {
                $ProjectName = $PotentialProjectDirName
            }

            $ProjectDirectoryItem = $DirItem
        }
    }

    # If an appropriate Project Folder doesn't already exist, create one
    if (!$ProjectDirectoryItem) {
        if (!$NewProjectDirectory) {
            $CurrentProjectDirectories = @($(Get-ChildItem -Directory).Name)
            if ($CurrentProjectDirectories.Count -gt 0) {
                $DirectoryName = NewUniqueString -ArrayOfStrings $CurrentProjectDirectories -PossibleNewUniqueString $SiteName
            }
            else {
                $DirectoryName = $SiteName
            }
            $NewProjectDirectory = $(Get-Location).Path + $DirSep + $DirectoryName
        }
        else {
            $NewProjectParentDir = $NewProjectDirectory | Split-Path -Parent
            if (!$(Test-Path $NewProjectParentDir)) {
                Write-Error "Unable to find the path $NewProjectParentDir! Halting!"
                $global:FunctionResult = "1"
                return
            }

            $CurrentProjectDirectories = @($(Get-ChildItem -Path $NewProjectParentDir -Directory).Name)
            if ($CurrentProjectDirectories.Count -gt 0) {
                $DirectoryName = NewUniqueString -ArrayOfStrings $CurrentProjectDirectories -PossibleNewUniqueString $SiteName
            }
            else {
                $DirectoryName = $SiteName
            }
            $NewProjectDirectory = $NewProjectParentDir + $DirSep + $DirectoryName
        }

        if (!$(Test-Path $NewProjectDirectory)) {
            try {
                $ProjectDirectoryItem = New-Item -ItemType Directory -Path $NewProjectDirectory -ErrorAction Stop
            }
            catch {
                Write-Error $_
                $global:FunctionResult = "1"
                return
            }
        }
        else {
            Write-Error "A directory with the name $NewProjectDirectory already exists! Halting!"
            $global:FunctionResult = "1"
            return
        }

        Push-Location $ProjectDirectoryItem.FullName

        $null = dotnet new console
        $null = dotnet restore
        $null = dotnet build
        $TestRun = dotnet run
        if ($TestRun -ne "Hello World!") {
            Write-Error "There was an issue creating a new dotnet console app in '$($(Get-Location).Path)'! Halting!"
            $global:FunctionResult = "1"
            return
        }
    }
    else {
        Push-Location $ProjectDirectoryItem.FullName
    }

    # Install any NuGetPackage dependencies
    # These packages will be found under $HOME/.nuget/packages/ after install, so they're not project specific
    # However, first make sure the project doesn't already include these packages
    $CSProjFileItem = Get-ChildItem -File -Filter "*.csproj"
    [xml]$CSProjParsedXml = Get-Content $CSProjFileItem
    $CurrentPackages = $CSProjParsedXml.Project.ItemGroup.PackageReference.Include

    $PackagesToInstall = @("Newtonsoft.Json","OpenScraping")
    foreach ($PackageName in $PackagesToInstall) {
        if ($CurrentPackages -notcontains $PackageName) {
            $null = dotnet add package $PackageName
        }
    }

    # Create Directory that will contain our .csx script and html parsing json config file (for example, dotnetapis.com.json)
    $WorkingDir = $ProjectDirectoryItem.FullName + $DirSep + "ScriptsConfigsAndOutput"
    if (!$(Test-Path $WorkingDir)) {
        try {
            $null = New-Item -ItemType Directory -Path $WorkingDir -ErrorAction Stop
        }
        catch {
            Write-Error $_
            $global:FunctionResult = "1"
            return
        }
    }

    Push-Location $WorkingDir

    # NOTE: OpenScraping 1.3.0 also installs System.Net.Http 4.3.2, System.Xml.XPath.XmlDocument 4.3.0, and HtmlAgilityPack 1.8.10

    $CSharpScriptPath = $WorkingDir + $DirSep + "$SiteName.csx"
    $HtmlParsingJsonConfigPath = $WorkingDir + $DirSep + "$SiteName.json"

    if ($HandleInfiniteScrolling) {
        # Get the InfiniteScrolling Lua Script and double-up on the double quotes
        $LuaScriptPSObjs = $(Get-Module HTMLToJson).Invoke({$LuaScriptPSObjects})
        $LuaScriptPrep = $($LuaScriptPSObjs | Where-Object {$_.LuaScriptName -eq 'InfiniteScrolling'}).LuaScriptContent
        $LuaScript = $LuaScriptPrep -replace '"','""'
    }

    if ($LuaScript) {
        $SplashEndPointString = 'string splashEndpoint = @"execute";'
        $PostDataString = 'var postData = JsonConvert.SerializeObject(new { url = url, timeout = 30, wait = 3, lua_source = luaScript });'
        $FinalLuaScript = $LuaScript -join "`n"
    }
    else {
        $SplashEndPointString = 'string splashEndpoint = @"render.html";'
        $PostDataString = 'var postData = JsonConvert.SerializeObject(new { url = url, timeout = 10, wait = 3 });'
        $FinalLuaScript = 'null'
    }

    # Write the CSharp Script
    $CSharpScript = @"
#r "nuget:Newtonsoft.Json,12.0.1"
#r "nuget:OpenScraping,1.3.0"

using System;
using System.Net;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using OpenScraping;
using OpenScraping.Config;

// XPath Cheat Sheet: http://ricostacruz.com/cheatsheets/xpath.html

string currDir = Directory.GetCurrentDirectory();
//string currDir = @"C:\Users\pddomain\Documents\LINQPad Queries";
string dirSeparator = System.IO.Path.DirectorySeparatorChar.ToString();

bool scrapeJavaScript = true;
if (scrapeJavaScript)
{
    string url = @"$UrlString";
    // Get Splash here: https://splash.readthedocs.io/en/stable/install.html
    string splashServer = @"$SplashServerUriString/";
    $SplashEndPointString
    string splashFinalUrl = splashServer + splashEndpoint;
    var request = (HttpWebRequest)WebRequest.Create(splashFinalUrl);
    request.Method = "POST";

    // For available Splash EndPoint Args (such as "timeout" and "wait" below), see: 
    // https://splash.readthedocs.io/en/stable/api.html
    string luaScript = @"
$FinalLuaScript";

    $PostDataString

    //Console.WriteLine(postData);
    var data = Encoding.ASCII.GetBytes(postData);
    // List of available content types here: https://en.wikipedia.org/wiki/Media_type
    request.ContentType = "application/json; charset=utf-8";
    //request.ContentType = "application/x-www-form-urlencoded; charset=utf-8";
    request.ContentLength = data.Length;

    using (var stream = request.GetRequestStream())
    {
        stream.Write(data, 0, data.Length);
    }
    var response = (HttpWebResponse)request.GetResponse();

    using (StreamReader sr = new StreamReader(response.GetResponseStream()))
    {
        var responseString = sr.ReadToEnd();
        using (StreamWriter sw = new StreamWriter(currDir + dirSeparator + "$SiteName.html"))
        {
            sw.Write(responseString);
        }
        //Console.WriteLine(responseString);
    }
}

// $SiteName.json contains the JSON configuration file pasted above
var jsonConfig = File.ReadAllText(currDir + dirSeparator + "$SiteName.json");
var config = StructuredDataConfig.ParseJsonString(jsonConfig);

var html = File.ReadAllText(currDir + dirSeparator + "$SiteName.html", Encoding.UTF8);

var openScraping = new StructuredDataExtractor(config);
var scrapingResults = openScraping.Extract(html);

Console.WriteLine(JsonConvert.SerializeObject(scrapingResults, Newtonsoft.Json.Formatting.Indented));
"@

    Set-Content -Path $CSharpScriptPath -Value $CSharpScript

    if ($XPathJsonConfigFile) {
        $HtmlParsingJsonConfig = Get-Content $XPathJsonConfigFile
    }
    if ($XPathJsonConfigString) {
        $HtmlParsingJsonConfig = $XPathJsonConfigString
    }

    Set-Content -Path $HtmlParsingJsonConfigPath -Value $HtmlParsingJsonConfig

    # Json Output
    dotnet-script $CSharpScriptPath

    # Cleanup
    if ($RemoveFileOutputs) {
        $HtmlFile = $WorkingDir + $DirSep + "$SiteName.html"
        $FilesToRemove = @($HtmlFile,$CSharpScriptPath,$HtmlParsingJsonConfigPath)
        foreach ($FilePath in $FilesToRemove) {
            if (Test-Path $FilePath) {
                $null = Remove-Item -Path $FilePath -Force
            }
        }
    }

    Pop-Location
    Pop-Location

}

# SIG # Begin signature block
# MIIMaAYJKoZIhvcNAQcCoIIMWTCCDFUCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUdCdy2wYN/IVL+z5Q1xNRrM5C
# 9e+gggndMIIEJjCCAw6gAwIBAgITawAAAERR8umMlu6FZAAAAAAARDANBgkqhkiG
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
# BDEWBBRqq1YH6aMUXDTPo8dSdX1y7H1RgjANBgkqhkiG9w0BAQEFAASCAQAcVjqD
# C09BiIYjMtuSi8eJh+GFodXuTaGacGiPSQuWViidIU8dT0Ia5B1iS0d0prV2mAtU
# J7ru+L7427IU83UNGl/gCXKRTtcx7oOi5UPkuxdzK1kpcp7evrGfOHbZzzHxfVkl
# iPrArZd9/x/GSX8K/CeSlhwwMN2wsaUHAVLCbz2Ycv7jUwymryJH4q35OHnJ4sal
# M7T+jglmrSMjdWdY8DJeGtqaURaNncuWB3VrND9y7AIooN50GXUXz8vrHtVoIwwf
# Rw7cIgqF4/Brux6moqZPA42eTYIy70iI/wsD9zJCT+WCB5uQFelNkurAIcW/TZsd
# JpQ/qe8LITZhjvhB
# SIG # End signature block
