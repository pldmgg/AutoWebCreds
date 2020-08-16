<#
    .SYNOPSIS
        Tests if a module contains a class resource.

    .PARAMETER ModulePath
        The path to the module to test.
#>
function Test-ModuleContainsClassResource
{
    [OutputType([Boolean])]
    [CmdletBinding()]
    param
    (
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [String]
        $ModulePath
    )

    $psm1Files = Get-Psm1FileList -FilePath $ModulePath

    foreach ($psm1File in $psm1Files)
    {
        if (Test-FileContainsClassResource -FilePath $psm1File.FullName)
        {
            return $true
        }
    }

    return $false
}

<#
    .SYNOPSIS
        Retrieves all .psm1 files under the given file path.

    .PARAMETER FilePath
        The root file path to gather the .psm1 files from.
#>
function Get-Psm1FileList
{
    [OutputType([Object[]])]
    [CmdletBinding()]
    param
    (
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [String]
        $FilePath
    )

    return Get-ChildItem -Path $FilePath -Filter '*.psm1' -File -Recurse
}

<#
    .SYNOPSIS
        Retrieves the parse errors for the given file.

    .PARAMETER FilePath
        The path to the file to get parse errors for.
#>
function Get-FileParseErrors
{
    [OutputType([System.Management.Automation.Language.ParseError[]])]
    [CmdletBinding()]
    param
    (
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [String]
        $FilePath
    )

    $parseErrors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($FilePath, [ref] $null, [ref] $parseErrors)

    return $parseErrors
}

<#
    .SYNOPSIS
        Retrieves all text files under the given root file path.

    .PARAMETER Root
        The root file path under which to retrieve all text files.

    .NOTES
        Retrieves all files with the '.gitignore', '.gitattributes', '.ps1', '.psm1', '.psd1',
        '.json', '.xml', '.cmd', or '.mof' file extensions.
#>
function Get-TextFilesList
{
    [OutputType([System.IO.FileInfo[]])]
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [String]
        $Root
    )

    $textFileExtensions = @('.gitignore', '.gitattributes', '.ps1', '.psm1', '.psd1', '.json', '.xml', '.cmd', '.mof','.md','.js','.yml')

    return Get-ChildItem -Path $Root -File -Recurse | Where-Object { $textFileExtensions -contains $_.Extension }
}

<#
    .SYNOPSIS
        Tests if a file is encoded in Unicode.

    .PARAMETER FileInfo
        The file to test.
#>
function Test-FileInUnicode {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [System.IO.FileInfo]$fileInfo
    )

    process {
        $path = $fileInfo.FullName
        $bytes = [System.IO.File]::ReadAllBytes($path)
        $zeroBytes = @($bytes -eq 0)
        return [bool]$zeroBytes.Length

    }
}

<#
    .SYNOPSIS
        Downloads and installs a module from PowerShellGallery using
        Nuget.

    .PARAMETER ModuleName
        Name of the module to install

    .PARAMETER DestinationPath
        Path where module should be installed
#>
function Install-ModuleFromPowerShellGallery
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [String]
        $ModuleName,

        [Parameter(Mandatory = $true)]
        [String]
        $DestinationPath
    )

    $nugetPath = 'nuget.exe'

    # Can't assume nuget.exe is available - look for it in Path
    if ($null -eq (Get-Command -Name $nugetPath -ErrorAction 'SilentlyContinue'))
    {
        # Is it in temp folder?
        $tempNugetPath = Join-Path -Path $env:temp -ChildPath $nugetPath

        if (-not (Test-Path -Path $tempNugetPath))
        {
            # Nuget.exe can't be found - download it to temp folder
            $nugetDownloadURL = 'http://nuget.org/nuget.exe'
            #Invoke-WebRequest -Uri $nugetDownloadURL -OutFile $tempNugetPath
            [Net.ServicePointManager]::SecurityProtocol = "tls12, tls11, tls"
            [System.Net.WebClient]::new().Downloadfile($nugetDownloadURL, $tempNugetPath)

            Write-Verbose -Message "nuget.exe downloaded at $tempNugetPath"

            $nugetPath = $tempNugetPath
        }
        else
        {
            Write-Verbose -Message "Using Nuget.exe found at $tempNugetPath"
        }
    }

    $moduleOutputDirectory = "$(Split-Path -Path $DestinationPath -Parent)\"

    $nugetSource = 'https://www.powershellgallery.com/api/v2'
    # Use Nuget.exe to install the module
    $null = & $nugetPath @( `
        'install', $ModuleName, `
        '-source', $nugetSource, `
        '-outputDirectory', $moduleOutputDirectory, `
        '-ExcludeVersion' `
        )

    if ($LASTEXITCODE -ne 0)
    {
        throw "Installation of module $ModuleName using Nuget failed with exit code $LASTEXITCODE."
    }

    Write-Verbose -Message "The module $ModuleName was installed using Nuget."
}

<#
    .SYNOPSIS
        Imports the PS Script Analyzer module.
        Installs the module from the PowerShell Gallery if it is not already installed.
#>
function Import-PSScriptAnalyzer
{
    [CmdletBinding()]
    param ()

    $psScriptAnalyzerModule = Get-Module -Name 'PSScriptAnalyzer' -ListAvailable

    if ($null -eq $psScriptAnalyzerModule)
    {
        Write-Verbose -Message 'Installing PSScriptAnalyzer from the PowerShell Gallery'
        $userProfilePSModulePathItem = Get-UserProfilePSModulePathItem
        $psScriptAnalyzerModulePath = Join-Path -Path $userProfilePSModulePathItem -ChildPath PSScriptAnalyzer
        Install-ModuleFromPowerShellGallery -ModuleName 'PSScriptAnalyzer' -DestinationPath $psScriptAnalyzerModulePath
    }

    $psScriptAnalyzerModule = Get-Module -Name 'PSScriptAnalyzer' -ListAvailable

    <#
        When using custom rules in PSSA the Get-Help cmdlet gets
        called by PSSA. This causes a warning to be thrown in AppVeyor.
        This warning does not cause a failure or error, but causes
        additional bloat to the analyzer output. To suppress this
        the registry key
        HKLM:\Software\Microsoft\PowerShell\DisablePromptToUpdateHelp
        should be set to 1 when running in AppVeyor.

        See this line from PSSA in GetExternalRule() method for more
        information:
        https://github.com/PowerShell/PSScriptAnalyzer/blob/development/Engine/ScriptAnalyzer.cs#L1120
    #>
    if ($env:APPVEYOR -eq $true)
    {
        Set-ItemProperty -Path HKLM:\Software\Microsoft\PowerShell -Name DisablePromptToUpdateHelp -Value 1
    }

    Import-Module -Name $psScriptAnalyzerModule
}

<#
    .SYNOPSIS
        Retrieves the list of suppressed PSSA rules in the file at the given path.

    .PARAMETER FilePath
        The path to the file to retrieve the suppressed rules of.
#>
function Get-SuppressedPSSARuleNameList
{
    [OutputType([String[]])]
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [String]
        $FilePath
    )

    $suppressedPSSARuleNames = [String[]]@()

    $fileAst = [System.Management.Automation.Language.Parser]::ParseFile($FilePath, [ref]$null, [ref]$null)

    # Overall file attributes
    $attributeAsts = $fileAst.FindAll({$args[0] -is [System.Management.Automation.Language.AttributeAst]}, $true)

    foreach ($attributeAst in $attributeAsts)
    {
        if ([System.Diagnostics.CodeAnalysis.SuppressMessageAttribute].FullName.ToLower().Contains($attributeAst.TypeName.FullName.ToLower()))
        {
            $suppressedPSSARuleNames += $attributeAst.PositionalArguments.Extent.Text
        }
    }

    return $suppressedPSSARuleNames
}

<#
    .SYNOPSIS
        Gets the current Pester Describe block name
#>
function Get-PesterDescribeName
{

    return Get-CommandNameParameterValue -Command 'Describe'
}

<#
    .SYNOPSIS
        Gets the opt-in status of the current pester Describe
        block. Writes a warning if the test is not opted-in.

    .PARAMETER OptIns
        An array of what is opted-in
#>
function Get-PesterDescribeOptInStatus
{
    param
    (
        [Parameter()]
        [System.String[]]
        $OptIns
    )

    $describeName = Get-PesterDescribeName
    $optIn = $OptIns -icontains $describeName
    if (-not $optIn)
    {
        $message = @"
Describe $describeName will not fail unless you opt-in.
To opt-in, create a '.MetaTestOptIn.json' at the root
of the repo in the following format:
[
     "$describeName"
]
"@
        Write-Warning -Message $message
    }

    return $optIn
}

<#
    .SYNOPSIS
        Gets the opt-in status of an option with the specified name. Writes
        a warning if the test is not opted-in.

    .PARAMETER OptIns
        An array of what is opted-in.

    .PARAMETER Name
        The name of the opt-in option to check the status of.
#>
function Get-OptInStatus
{
    param
    (
        [Parameter()]
        [System.String[]]
        $OptIns,

        [Parameter(Mandatory = $true)]
        [System.String]
        $Name
    )

    $optIn = $OptIns -icontains $Name
    if (-not $optIn)
    {
        $message = @"
$Name will not fail unless you opt-in.
To opt-in, create a '.MetaTestOptIn.json' at the root
of the repo in the following format:
[
     "$Name"
]
"@
        Write-Warning -Message $message
    }

    return $optIn
}

<#
    .SYNOPSIS
        Gets the value of the Name parameter for the specified command in the stack.

    .PARAMETER Command
        The name of the command to find the Name parameter for.
#>
function Get-CommandNameParameterValue
{
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Command
    )

    $commandStackItem = (Get-PSCallStack).Where{ $_.Command -eq $Command }
    $commandArgumentNameValues = $commandStackItem.Arguments.TrimStart('{',' ').TrimEnd('}',' ') -split '\s*,\s*'
    $nameParameterValue = ($commandArgumentNameValues.Where{ $_ -like 'name=*' } -split '=')[-1]
    return $nameParameterValue
}

<#
    .SYNOPSIS
        Returns first the item in $env:PSModulePath that matches the given Prefix ($env:PSModulePath is list of semicolon-separated items).
        If no items are found, it reports an error.
    .PARAMETER Prefix
        Path prefix to look for.
    .NOTES
        If there are multiple matching items, the function returns the first item that occurs in the module path; this matches the lookup
        behavior of PowerSHell, which looks at the items in the module path in order of occurrence.
    .EXAMPLE
        If $env:PSModulePath is
            C:\Program Files\WindowsPowerShell\Modules;C:\Users\foo\Documents\WindowsPowerShell\Modules;C:\Windows\system32\WindowsPowerShell\v1.0\Modules
        then
            Get-PSModulePathItem C:\Users
        will return
            C:\Users\foo\Documents\WindowsPowerShell\Modules
#>
function Get-PSModulePathItem
{
    param
    (
        [Parameter(Mandatory = $true, Position = 0)]
        [System.String]
        $Prefix
    )

    $item = $env:PSModulePath.Split(';') |
        Where-Object -FilterScript { $_ -like "$Prefix*" } |
        Select-Object -First 1

    if (-not $item)
    {
        Write-Error -Message "Cannot find the requested item in the PowerShell module path.`n`$env:PSModulePath = $env:PSModulePath"
    }

    return $item
}

<#
    .SYNOPSIS
        Returns the first item in $env:PSModulePath that is a path under $env:USERPROFILE.
        If no items are found, it reports an error.
    .EXAMPLE
        If $env:PSModulePath is
            C:\Program Files\WindowsPowerShell\Modules;C:\Users\foo\Documents\WindowsPowerShell\Modules;C:\Windows\system32\WindowsPowerShell\v1.0\Modules
        and the current user is 'foo', then
            Get-UserProfilePSModulePathItem
        will return
            C:\Users\foo\Documents\WindowsPowerShell\Modules
#>
function Get-UserProfilePSModulePathItem {
    param()

    return Get-PSModulePathItem -Prefix $env:USERPROFILE
}

<#
    .SYNOPSIS
        Returns the first item in $env:PSModulePath that is a path under $env:USERPROFILE.
        If no items are found, it reports an error.
    .EXAMPLE
        If $env:PSModulePath is
            C:\Program Files\WindowsPowerShell\Modules;C:\Users\foo\Documents\WindowsPowerShell\Modules;C:\Windows\system32\WindowsPowerShell\v1.0\Modules
        then
            Get-PSHomePSModulePathItem
        will return
            C:\Windows\system32\WindowsPowerShell\v1.0\Modules
#>
function Get-PSHomePSModulePathItem {
    param()

    return Get-PSModulePathItem -Prefix $global:PSHOME
}

<#
    .SYNOPSIS
        Tests if a file contains Byte Order Mark (BOM).

    .PARAMETER FilePath
        The file path to evaluate.
#>
function Test-FileHasByteOrderMark
{
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $FilePath
    )

    # This reads the first three bytes of the first row.
    $firstThreeBytes = Get-Content -Path $FilePath -Encoding Byte -ReadCount 3 -TotalCount 3

    # Check for the correct byte order (239,187,191) which equal the Byte Order Mark (BOM).
    return ($firstThreeBytes[0] -eq 239 `
        -and $firstThreeBytes[1] -eq 187 `
        -and $firstThreeBytes[2] -eq 191)
}

<#
    .SYNOPSIS
        This returns a string containing the relative path from the module root.

    .PARAMETER FilePath
        The file path to remove the module root path from.

    .PARAMETER ModuleRootFilePath
        The root path to remove from the file path.
#>
function Get-RelativePathFromModuleRoot
{
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $FilePath,

        [Parameter(Mandatory = $true)]
        [System.String]
        $ModuleRootFilePath
    )

    <#
        Removing the module root path from the file path so that the path
        doesn't get so long in the Pester output.
    #>
    return ($FilePath -replace [Regex]::Escape($ModuleRootFilePath),'').Trim('\')
}

<#
    .SYNOPSIS
        Installs dependent modules in the user scope, if not already available
        and only if run on an AppVeyor build worker. If not run on a AppVeyor
        build worker, it will output a warning saying that the users must
        install the correct module to be able to run the test.

    .PARAMETER Module
        An array of hash tables containing one or more dependent modules that
        should be installed. The correct array is returned by the helper
        function Get-ResourceModulesInConfiguration.

        Hash table should be in this format. Where property Name is mandatory
        and property Version is optional.

        @{
            Name    = 'xStorage'
            [Version = '3.2.0.0']
        }
#>
function Install-DependentModule
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Collections.Hashtable[]]
        $Module
    )

    # Check any additional modules required are installed
    foreach ($requiredModule in $Module)
    {
        $getModuleParameters = @{
            Name = $requiredModule.Name
            ListAvailable = $true
            ErrorAction = 'SilentlyContinue'
        }

        if ($requiredModule.ContainsKey('Version'))
        {
            $requiredModuleExist = `
                Get-Module @getModuleParameters |
                    Where-Object -FilterScript {
                        $_.Version -eq $requiredModule.Version
                    }
        }
        else
        {
            $requiredModuleExist = Get-Module @getModuleParameters
        }

        if (-not ($requiredModuleExist))
        {
            # The required module is missing from this machine
            if ($requiredModule.ContainsKey('Version'))
            {
                $requiredModuleName = ('{0} version {1}' -f $requiredModule.Name, $requiredModule.Version)
            }
            else
            {
                $requiredModuleName = ('{0}' -f $requiredModule.Name)
            }

            if ($env:APPVEYOR -eq $true)
            {
                <#
                    Tests are running in AppVeyor so just install the module.
                    If not installed by using Force then the error message
                    "User declined to install untrusted module (<module name>)."
                    is thrown
                #>
                $installModuleParameters = @{
                    Name  = $requiredModule.Name
                    Force = $true
                }

                if ($requiredModule.ContainsKey('Version'))
                {
                    $installModuleParameters['RequiredVersion'] = $requiredModule.Version
                }

                Write-Verbose -Message "Installing module $requiredModuleName required to compile a configuration." -Verbose
                try
                {
                    Install-Module @installModuleParameters -Scope CurrentUser
                }
                catch
                {
                    throw "An error occurred installing the required module $($requiredModuleName) : $_"
                }
            }
            else
            {
                # Warn the user that the test fill fail
                Write-Warning -Message ("To be able to compile a configuration the resource module $requiredModuleName " + `
                    'is required but it is not installed on this computer. ' + `
                    'The test that is dependent on this module will fail until the required module is installed. ' + `
                    'Please install it from the PowerShell Gallery to enable these tests to pass.')
            } # if
        } # if
    } # foreach
}

<#
    .SYNOPSIS
        The is a wrapper to set $env:PSModulePath both in current session and
        machine wide.
        This is needed to be able to mock the function in the unit tests.

    .PARAMETER Path
        A string with all the paths separated by semi-colons.

    .PARAMETER Machine
        If set the PSModulePath will be changed machine wide. If not set, only
        the current session will be changed.

    .EXAMPLE
        Set-PSModulePath -Path '<Path 1>;<Path 2>'

    .EXAMPLE
        Set-PSModulePath -Path '<Path 1>;<Path 2>' -Machine
#>
function Set-PSModulePath
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $Path,

        [Parameter()]
        [Switch]
        $Machine
    )

    if ($Machine.IsPresent)
    {
        [System.Environment]::SetEnvironmentVariable('PSModulePath', $Path, [System.EnvironmentVariableTarget]::Machine)
    }
    else
    {
        $env:PSModulePath = $Path
    }
}

<#
    .SYNOPSIS
        Writes a message to the console in a standard format.

    .PARAMETER Message
        The message to write to the console.

    .PARAMETER ForegroundColor
        The text color to use when writing the message to the console. Defaults
        to 'Yellow'.
#>
function Write-Info
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory=$true, Position=0)]
        [System.String]
        $Message,

        [Parameter()]
        [System.String]
        $ForegroundColor = 'Yellow'
    )

    Write-Host -ForegroundColor $ForegroundColor -Object "[Build Info] [UTC $([System.DateTime]::UtcNow)] $message"
}

<#
    .SYNOPSIS
        Retrieves the localized string data based on the machine's culture.
        Falls back to en-US strings if the machine's culture is not supported.

    .PARAMETER ModuleName
        The name of the module as it appears before '.strings.psd1' of the localized string file.
        For example:
            For module: DscResource.Container

    .PARAMETER ModuleRoot
        The module root path where to expect to find the culture folder.
#>
function Get-LocalizedData
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $ModuleName,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $ModuleRoot
    )

    $localizedStringFileLocation = Join-Path -Path $ModuleRoot -ChildPath $PSUICulture

    if (-not (Test-Path -Path $localizedStringFileLocation))
    {
        # Fallback to en-US
        $localizedStringFileLocation = Join-Path -Path $ModuleRoot -ChildPath 'en-US'
    }

    Import-LocalizedData `
        -BindingVariable 'localizedData' `
        -FileName "$ModuleName.strings.psd1" `
        -BaseDirectory $localizedStringFileLocation

    return $localizedData
}

Export-ModuleMember -Function @(
    'Install-ModuleFromPowerShellGallery'
    'Test-ModuleContainsClassResource'
    'Get-Psm1FileList'
    'Get-FileParseErrors'
    'Get-TextFilesList'
    'Test-FileInUnicode'
    'Import-PSScriptAnalyzer'
    'Get-SuppressedPSSARuleNameList'
    'Get-PesterDescribeOptInStatus'
    'Get-OptInStatus'
    'Get-UserProfilePSModulePathItem'
    'Get-PSHomePSModulePathItem'
    'Test-FileHasByteOrderMark'
    'Get-RelativePathFromModuleRoot'
    'Get-ResourceModulesInConfiguration'
    'Install-DependentModule'
    'Set-PSModulePath'
    'Write-Info'
    'Get-LocalizedData'
)

# SIG # Begin signature block
# MIIMaAYJKoZIhvcNAQcCoIIMWTCCDFUCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUx5sqUYELbZFAg5h3DP0aRLrp
# nSmgggndMIIEJjCCAw6gAwIBAgITawAAAERR8umMlu6FZAAAAAAARDANBgkqhkiG
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
# BDEWBBStWn79DYuPfwez9BZ/2TB+4y38tzANBgkqhkiG9w0BAQEFAASCAQBZ3v2h
# /bMoebgVVdZbr9quWmdjyk6gwzHvRyX9yGz5bFdul0ttV86FTu7cMV2aZJg7RAEF
# Azcz5vEMzMm8FlyGm93NgQeBZHrcxSCd+m61uN6/BeAbicx/gjvQnw/lY2t8wj7k
# 44NaZFvXkiuS8UPPYRua91yJl5ZQR90/tNiR1ea1fRpHiGhCTfv+KxTBjgkd1Cxj
# McDInSjaxTI0YKZ45hjT6Pmo1HZ76HSY26e8efRByJBVS3STjVWH4ydEqWIjViYU
# WtgJu5t0zzDKk03aAln5yQvrYhQWqGCQwqiGhO4ZJj0wBg4AUqWunVNkd3fM7vB/
# gBdRNB52JnA0vZr+
# SIG # End signature block
