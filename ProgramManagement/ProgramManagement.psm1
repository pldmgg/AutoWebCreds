[Net.ServicePointManager]::SecurityProtocol = "tls12, tls11, tls"

# Get public and private function definition files.
[array]$Public  = Get-ChildItem -Path "$PSScriptRoot\Public\*.ps1" -ErrorAction SilentlyContinue
[array]$Private = Get-ChildItem -Path "$PSScriptRoot\Private\*.ps1" -ErrorAction SilentlyContinue
$ThisModule = $(Get-Item $PSCommandPath).BaseName

# Dot source the Private functions
foreach ($import in $Private) {
    try {
        . $import.FullName
    }
    catch {
        Write-Error -Message "Failed to import function $($import.FullName): $_"
    }
}

[System.Collections.Arraylist]$ModulesToInstallAndImport = @()
if (Test-Path "$PSScriptRoot\module.requirements.psd1") {
    $ModuleManifestData = Import-PowerShellDataFile "$PSScriptRoot\module.requirements.psd1"
    $ModuleManifestData.Keys | Where-Object {$_ -ne "PSDependOptions"} | foreach {$null = $ModulesToinstallAndImport.Add($_)}
}

if ($ModulesToInstallAndImport.Count -gt 0) {
    # Set $env:PSModulePath correctly
    # Determine installed PowerShell Core Versions
    $PSCoreDirItems = @(Get-ChildItem -Path "$env:ProgramFiles\Powershell" -Directory | Where-Object {$_.Name -match "[0-9]"})
    $LatestPSCoreDirPath = $($PSCoreDirItems | Sort-Object -Property CreationTime)[-1].FullName
    $PSCoreUserDocsModulePath = "$HOME\Documents\PowerShell\Modules"
    $WinPSUserDocsModulePath = "$HOME\Documents\WindowsPowerShell\Modules"
    $LatestPSCoreSystemPath = "$LatestPSCoreDirPath\Modules"
    $LatestWinPSSystemPath = "$env:ProgramFiles\WindowsPowerShell\Modules"

    $AllPSModulePaths = @(
        $PSCoreUserDocsModulePath
        $WinPSUserDocsModulePath
        $($LatestPSCoreDirPath | Split-Path -Parent)
        $LatestPSCoreSystemPath
        $LatestWinPSSystemPath
        "$env:SystemRoot\system32\WindowsPowerShell\v1.0\Modules"
    )

    foreach ($ModPath in $AllPSModulePaths) {
        if (![bool]$($($env:PSModulePath -split ";") -match [regex]::Escape($ModPath))) {
            $env:PSModulePath = "$ModPath;$env:PSModulePath"
        }
    }

    # Attempt to import the Module Dependencies
    foreach ($ModuleName in $ModulesToInstallAndImport) {
        # Make sure it's installed
        $GetModResult = @(Get-Module -ListAvailable -Name $ModuleName)
        if ($GetModResult.Count -eq 0) {
            try {
                $null = Install-Module -Name $ModuleName -Scope CurrentUser -AllowClobber -Force -ErrorAction Stop -WarningAction SilentlyContinue
            }
            catch {
                # Try Manual Install
                $DLDir = $([IO.Path]::Combine([IO.Path]::GetTempPath(), [IO.Path]::GetRandomFileName()) -split [regex]::Escape('.'))[0]
                $null = [IO.Directory]::CreateDirectory($tempDirectory)

                $InstallSplatParams = @{
                    ModuleName          = $ModuleName
                    DownloadDirectory   = $DLDir
                    ErrorAction         = 'Stop'
                    WarningAction       = 'SilentlyContinue'
                }
                
                try {
                    $null = ManualPSGalleryModuleInstall @InstallSplatParams
                }
                catch {
                    try {
                        # It might be a PreRelease
                        $InstallSplatParams.Add('PreRelease',$True)
                        $null = ManualPSGalleryModuleInstall @InstallSplatParams
                    }
                    catch {
                        Write-Error "Problem installing Module dependency $ModuleName ! Halting!"
                        return
                    }
                }
            }

            $GetModResult = @(Get-Module -ListAvailable -Name $ModuleName)
            if ($GetModResult.Count -eq 0) {
                Write-Error "Problem installing Module dependency $ModuleName ! Halting!"
                return
            }
        }
        
        # Import the Module        
        try {
            Import-Module -Name $ModuleName -ErrorAction Stop
        }
        catch {
            # If we're in PSCore, then we need to potentially try the -UseWindowsPowerShell switch
            if ($PSVersionTable.PSEdition -eq "Core") {
                try {
                    Import-Module -Name $ModuleName -UseWindowsPowerShell -ErrorAction Stop
                }
                catch {
                    Write-Error "Problem importing Module dependency $ModuleName ! Halting!"
                    return
                }
            }
            else {
                Write-Error "Problem importing Module dependency $ModuleName ! Halting!"
                return
            }
        }
        
    }
}

# Public Functions



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


# Outputs [System.Collections.ArrayList]$ExePath
function Get-ExePath {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory=$True)]
        [string]$ProgramName,

        [Parameter(Mandatory=$True)]
        [string]$OriginalSystemPath,

        [Parameter(Mandatory=$True)]
        [string]$OriginalEnvPath,

        [Parameter(Mandatory=$True)]
        [string]$FinalCommandName,

        [Parameter(Mandatory=$False)]
        [string]$ExpectedInstallLocation
    )

    # ...search for it in the $ExpectedInstallLocation if that parameter is provided by the user...
    if ($ExpectedInstallLocation) {
        if (Test-Path $ExpectedInstallLocation) {
            [System.Collections.ArrayList][Array]$ExePath = $(Get-ChildItem -Path $ExpectedInstallLocation -File -Recurse -Filter "*$FinalCommandName.exe").FullName
        }
    }
    else {
        # ...then we can compare $OriginalSystemPath to the current System PATH to potentially
        # figure out which directories *might* contain the main executable.
        $OriginalSystemPathArray = $OriginalSystemPath -split ";" | foreach {if (-not [System.String]::IsNullOrWhiteSpace($_)) {$_}}
        $OriginalEnvPathArray = $OriginalEnvPath -split ";" | foreach {if (-not [System.String]::IsNullOrWhiteSpace($_)) {$_}}

        $CurrentSystemPath = $(Get-ItemProperty -Path 'Registry::HKEY_LOCAL_MACHINE\System\CurrentControlSet\Control\Session Manager\Environment' -Name PATH).Path
        $CurrentSystemPathArray = $CurrentSystemPath -split ";" | foreach {if (-not [System.String]::IsNullOrWhiteSpace($_)) {$_}}
        $CurrentEnvPath = $env:Path
        $CurrentEnvPathArray = $CurrentEnvPath -split ";" | foreach {if (-not [System.String]::IsNullOrWhiteSpace($_)) {$_}}
        

        $OriginalVsCurrentSystemPathComparison = Compare-Object $OriginalSystemPathArray $CurrentSystemPathArray
        $OriginalVsCurrentEnvPathComparison = Compare-Object $OriginalEnvPathArray $CurrentEnvPathArray

        [System.Collections.ArrayList]$DirectoriesToSearch = @()
        if ($OriginalVsCurrentSystemPathComparison -ne $null) {
            # => means that $CurrentSystemPathArray has some new directories
            [System.Collections.ArrayList][Array]$NewSystemPathDirs = $($OriginalVsCurrentSystemPathComparison | Where-Object {$_.SideIndicator -eq "=>"}).InputObject
        
            if ($NewSystemPathDirs.Count -gt 0) {
                foreach ($dir in $NewSystemPathDirs) {
                    $null = $DirectoriesToSearch.Add($dir)
                }
            }
        }
        if ($OriginalVsCurrentEnvPathComparison -ne $null) {
            # => means that $CurrentEnvPathArray has some new directories
            [System.Collections.ArrayList][Array]$NewEnvPathDirs = $($OriginalVsCurrentEnvPathComparison | Where-Object {$_.SideIndicator -eq "=>"}).InputObject
        
            if ($NewEnvPathDirs.Count -gt 0) {
                foreach ($dir in $NewEnvPathDirs) {
                    $null = $DirectoriesToSearch.Add($dir)
                }
            }
        }

        if ($DirectoriesToSearch.Count -gt 0) {
            $DirectoriesToSearchFinal = $($DirectoriesToSearch | Sort-Object | Get-Unique) | foreach {if (Test-Path $_ -ErrorAction SilentlyContinue) {$_}}
            $DirectoriesToSearchFinal = $DirectoriesToSearchFinal | Where-Object {$_ -match $ProgramName}

            [System.Collections.ArrayList]$ExePath = @()
            foreach ($dir in $DirectoriesToSearchFinal) {
                [Array]$ExeFiles = $(Get-ChildItem -Path $dir -File -Filter "*$FinalCommandName.exe").FullName
                if ($ExeFiles.Count -gt 0) {
                    $null = $ExePath.Add($ExeFiles)
                }
            }

            # If there IS a difference in original vs current System PATH / $Env:Path, but we 
            # still DO NOT find the main executable in those diff directories (i.e. $ExePath is still not set),
            # it's possible that the name of the main executable that we're looking for is actually
            # incorrect...in which case just tell the user that we can't find the expected main
            # executable name and provide a list of other .exe files that we found in the diff dirs.
            if (!$ExePath -or $ExePath.Count -eq 0) {
                [System.Collections.ArrayList]$ExePath = @()
                foreach ($dir in $DirectoriesToSearchFinal) {
                    [Array]$ExeFiles = $(Get-ChildItem -Path $dir -File -Filter "*.exe").FullName
                    foreach ($File in $ExeFiles) {
                        $null = $ExePath.Add($File)
                    }
                }
            }
        }
    }

    $ExePath | Sort-Object | Get-Unique
}


<#
    .SYNOPSIS
        This function gathers information about programs installed on the specified Hosts by inspecting
        the Windows Registry.

        If you do NOT use the -ProgramTitleSearchTerm parameter, information about ALL programs installed on
        the specified hosts will be returned.

    .DESCRIPTION
        See .SYNOPSIS

    .NOTES

        If you're looking for detailed information about an installed Program, or if you're looking to generate a list
        that closely resembles what you see in the 'Control Panel' 'Programs and Features' GUI, use this function.

    .PARAMETER ProgramTitleSearchTerm
        This parameter is OPTIONAL.

        This parameter takes a string that loosely matches the Program Name that you would like
        to gather information about. You can use regex with with this parameter.

        If you do NOT use this parameter, a list of ALL programs installed on the 

    .PARAMETER HostName
        This parameter is OPTIONAL, but is defacto mandatory since it defaults to $env:ComputerName.

        This parameter takes an array of string representing DNS-Resolveable host names that this function will
        attempt to gather Program Installation information from.

    .PARAMETER AllADWindowsComputers
        This parameter is OPTIONAL.

        This parameter is a switch. If it is used, this function will use the 'Get-ADComputer' cmdlet from the ActiveDirectory
        PowerShell Module (from RSAT) in order to generate a list of Computers on the domain. It will then get program information
        from each of those computers.

    .EXAMPLE
        # Open an elevated PowerShell Session, import the module, and -

        PS C:\Users\zeroadmin> Get-InstalledProgramsFromRegistry -ProgramTitleSearchTerm openssh
#>
function Get-InstalledProgramsFromRegistry {
    [CmdletBinding(
        PositionalBinding=$True,
        DefaultParameterSetName='Default Param Set'
    )]
    Param(
        [Parameter(
            Mandatory=$False,
            ParameterSetName='Default Param Set'
        )]
        [string]$ProgramTitleSearchTerm,

        [Parameter(
            Mandatory=$False,
            ParameterSetName='Default Param Set'
        )]
        [string[]]$HostName,

        [Parameter(
            Mandatory=$False,
            ParameterSetName='Secondary Param Set'
        )]
        [switch]$AllADWindowsComputers
    )

    ##### BEGIN Variable/Parameter Transforms and PreRun Prep #####

    if (!$HostName -and !$AllADWindowsComputers) {
        [string[]]$HostName = @($env:ComputerName)
    }

    $uninstallWow6432Path = "\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    $uninstallPath = "\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"

    $RegPaths = @(
        "HKLM:$uninstallWow6432Path",
        "HKLM:$uninstallPath",
        "HKCU:$uninstallWow6432Path",
        "HKCU:$uninstallPath"
    )
    
    ##### END Variable/Parameter Transforms and PreRun Prep #####

    ##### BEGIN Main Body #####
    # Get a list of Windows Computers from AD
    if ($AllADWindowsComputers) {
        if (!$(Get-Module -ListAvailable ActiveDirectory)) {
            Write-Error "The ActiveDirectory PowerShell Module (from RSAT) is not installed on this machine (i.e. $env:ComputerName)! Unable to get a list of Computers from Active Directory. Halting!"
            $global:FunctionResult = "1"
            return
        }
        if (!$(Get-Module ActiveDirectory)) {
            try {
                Import-Module ActiveDirectory -ErrorAction Stop
            }
            catch {
                Write-Error $_
                Write-Error "Problem importing the PowerShell Module 'ActiveDirectory'! Halting!"
                $global:FunctionResult = "1"
                return
            }
        }
        if (!$(Get-Command Get-ADComputer)) {
            Write-Error "Unable to find the cmdlet 'Get-ADComputer'! Unable to get a list of Computers from Active Directory. Halting!"
            $global:FunctionResult = "1"
            return
        }
        [array]$ComputersArray = $(Get-ADComputer -Filter * -Property * | Where-Object {$_.OperatingSystem -like "*Windows*"}).Name
    }
    else {
        [array]$ComputersArray = $HostName
    }

    foreach ($computer in $ComputersArray) {
        if ($computer -eq $env:ComputerName -or $computer.Split("\.")[0] -eq $env:ComputerName) {
            try {
                $InstalledPrograms = foreach ($regpath in $RegPaths) {if (Test-Path $regpath) {Get-ItemProperty $regpath}}
                if (!$InstalledPrograms) {
                    throw
                }
            }
            catch {
                Write-Warning "Unable to find registry path(s) on $computer. Skipping..."
                continue
            }
        }
        else {
            try {
                $InstalledPrograms = Invoke-Command -ComputerName $computer -ScriptBlock {
                    foreach ($regpath in $RegPaths) {
                        if (Test-Path $regpath) {
                            Get-ItemProperty $regpath
                        }
                    }
                } -ErrorAction SilentlyContinue
                if (!$InstalledPrograms) {
                    throw
                }
            }
            catch {
                Write-Warning "Unable to connect to $computer. Skipping..."
                continue
            }
        }

        if ($ProgramTitleSearchTerm) {
            $InstalledPrograms | Where-Object {$_.DisplayName -match $ProgramTitleSearchTerm}
        }
        else {
            $InstalledPrograms
        }
    }

    ##### END Main Body #####

}


<#
    .SYNOPSIS
        Installs the Chocolatey Command Line (i.e. choco.exe and related binaries)

    .DESCRIPTION
        See .SYNOPSIS

    .NOTES

    .EXAMPLE
        # Open an elevated PowerShell Session, import the module, and -

        PS C:\Users\zeroadmin> Install-ChocolateyCmdLine

    .EXAMPLE
        # Open an elevated PowerShell Session, import the module, and -
        
        PS C:\Users\zeroadmin> Install-ChocolateyCmdLine

#>
function Install-ChocolateyCmdLine {
    [CmdletBinding()]
    Param ()

    ##### BEGIN Variable/Parameter Transforms and PreRun Prep #####
    # Invoke-WebRequest fix...
    [Net.ServicePointManager]::SecurityProtocol = "tls12, tls11, tls"

    if (!$(GetElevation)) {
        Write-Error "The $($MyInvocation.MyCommand.Name) function must be ran from an elevated PowerShell Session (i.e. 'Run as Administrator')! Halting!"
        $global:FunctionResult = "1"
        return
    }

    try {
        Invoke-Expression $((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1')) -ErrorAction Stop
    }
    catch {
        Write-Error $_
        return
    }

    if (![bool]$(Get-Command choco -ErrorAction SilentlyContinue)) {
        # The above install.ps1 probably already updated PATH, but it may not be updated in this particular PowerShell session
        # So, start a new PowerShell session and see if choco is available
        $ChocoCheck = Start-Job -Name ChocoPathTest -ScriptBlock {Get-Command choco} | Wait-Job | Receive-Job

        # $ChocoCheck.Source should return C:\ProgramData\chocolatey\bin\choco.exe
        if (!$ChocoCheck) {
            try {
                Write-Host "Refreshing `$env:Path..."
                $null = Update-ChocolateyEnv -ErrorAction Stop
            }
            catch {
                Write-Warning $_.Exception.Message
                Write-Warning "Please start another PowerShell session in order to use the Chocolatey cmdline."
            }
        }

        # If we STILL can't find choco.exe, then give up...
        if (![bool]$(Get-Command choco -ErrorAction SilentlyContinue)) {
            Write-Warning "Please start another PowerShell session in order to use the Chocolatey cmdline."
        }
        else {
            Write-Host "Finished installing Chocolatey CmdLine." -ForegroundColor Green

            # Make sure we have the latest version
            Write-Host "Ensuring we have the latest version of chocolatey..."
            cup chocolatey -y
        }
    }
    else {
        Write-Host "Finished installing Chocolatey CmdLine." -ForegroundColor Green

        # Make sure we have the latest version
        Write-Host "Ensuring we have the latest version of chocolatey..."
        cup chocolatey -y
    }

    ##### END Main Body #####
}


<#
    .SYNOPSIS
        Install a Program using PowerShellGet/PackageManagement Modules OR the Chocolatey CmdLine.

    .DESCRIPTION
        This function was written to make program installation on Windows as easy and generic
        as possible by leveraging existing solutions such as PackageManagement/PowerShellGet
        and the Chocolatey CmdLine.

        For any scenario in which the Chocolatey CmdLine is used, if Chocolatey is not aleady installed
        on the machine, it will be installed.

        Default behavior for this function (using only the -ProgramName parameter) is to:
        - Try installation via Chocolatey as long as the program isn't already installed via PSGet.
        - If the program is already installed via PSGet and the update via PSGet fails, then
        the program will be uninstalled via PSGet and reinstalled via Chocolatey

        If you explicitly specify -UsePowerShellGet, then:
        - PSGet will be used for the install
        - If PSGet fails, then the function will give up

        If you explicitly specify -UseChocolateyCmdLine, then:
        - The Chocolatey CmdLine will be used for the install
        - If Chocolatey fails, then the function will give up

    .NOTES

    .PARAMETER ProgramName
        This parameter is MANDATORY.

        This paramter takes a string that represents the name of the program that you'd like to install.

    .PARAMETER CommandName
        This parameter is OPTIONAL.

        This parameter takes a string that represents the name of the main executable for the installed
        program. For example, if you are installing 'openssh', the value of this parameter should be 'ssh'.

    .PARAMETER PreRelease
        This parameter is OPTIONAL.

        This parameter is a switch. If used, the latest version of the program in the pre-release branch
        (if one exists) will be installed.

    .PARAMETER GetPenultimateVersion
        This parameter is OPTIONAL.

        This parameter is a switch. If used, the version preceding the latest version of the program will
        be installed - unless Chocolatey is being used, in which case this switch will be ignored.

    .PARAMETER UsePowerShellGet
        This parameter is OPTIONAL.

        This parameter is a switch. If used the function will attempt program installation using ONLY
        PackageManagement/PowerShellGet Modules. If installation using those modules fails, the function
        halts and returns the relevant error message(s).

        Installation via the Chocolatey CmdLine will NOT be attempted.

    .PARAMETER UseChocolateyCmdLine
        This parameter is OPTIONAL.

        This parameter is a switch. If used the function will attempt installation using ONLY
        the Chocolatey CmdLine. (The Chocolatey CmdLine will be installed if it is not already).
        If installation via the Chocolatey CmdLine fails for whatever reason,
        the function halts and returns the relevant error message(s).

    .PARAMETER ExpectedInstallLocation
        This parameter is OPTIONAL.

        This parameter takes a string that represents the full path to a directory that will contain
        main executable associated with the program to be installed. This directory should be the
        immediate parent directory of the .exe.

        If you are **absolutely certain** you know where the Main Executable for the program to be installed
        will be, then use this parameter. STDOUT (i.e. Write-Host) will provide instructions on adding this
        location to the system PATH and PowerShell's $env:Path.

    .PARAMETER ScanCommonInstallDirs
        This parameter is OPTIONAL.

        This parameter is a switch. If used, common install locations will be searched for the Program's main .exe.
        If found, STDOUT (i.e. Write-Host) will provide instructions on adding this location to the system PATH and
        PowerShell's $env:Path.

    .PARAMETER Force
        This parameter is OPTIONAL.

        This parameter is a switch. If used, install will be attempted for the specified -ProgramName even if it is
        already installed.

    .EXAMPLE
        # Open an elevated PowerShell Session, import the module, and -

        PS C:\Users\zeroadmin> Install-Program -ProgramName kubernetes-cli -CommandName kubectl.exe

    .EXAMPLE
        # Open an elevated PowerShell Session, import the module, and -

        PS C:\Users\zeroadmin> Install-Program -ProgramName awscli -CommandName aws.exe -UsePowerShellGet

    .EXAMPLE
        # Open an elevated PowerShell Session, import the module, and -

        PS C:\Users\zeroadmin> Install-Program -ProgramName VisualStudioCode -CommandName Code.exe -UseChocolateyCmdLine

    .EXAMPLE
        # If the Program Name and Main Executable are the same, then this is all you need for the function to find the Main Executable
        
        PS C:\Users\zeroadmin> Install-Program -ProgramName vagrant

#>
function Install-Program {
    [CmdletBinding()]
    Param (
        [Parameter(
            Mandatory=$True,
            Position=0
        )]
        [string]$ProgramName,

        [Parameter(Mandatory=$False)]
        [string]$CommandName,

        [Parameter(Mandatory=$False)]
        [switch]$PreRelease,

        [Parameter(Mandatory=$False)]
        [switch]$GetPenultimateVersion,

        [Parameter(Mandatory=$False)]
        [switch]$UsePowerShellGet,

        [Parameter(Mandatory=$False)]
        [switch]$UseChocolateyCmdLine,

        [Parameter(Mandatory=$False)]
        [string]$ExpectedInstallLocation,

        [Parameter(Mandatory=$False)]
        [switch]$ScanCommonInstallDirs,

        [Parameter(Mandatory=$False)]
        [switch]$Force
    )

    ##### BEGIN Native Helper Functions #####

    # The below function adds Paths from System PATH that aren't present in $env:Path (this probably shouldn't
    # be an issue, because $env:Path pulls from System PATH...but sometimes profile.ps1 scripts do weird things
    # and also $env:Path wouldn't necessarily be updated within the same PS session where a program is installed...)
    function Synchronize-SystemPathEnvPath {
        $SystemPath = $(Get-ItemProperty -Path 'Registry::HKEY_LOCAL_MACHINE\System\CurrentControlSet\Control\Session Manager\Environment' -Name PATH).Path
        
        $SystemPathArray = $SystemPath -split ";" | foreach {if (-not [System.String]::IsNullOrWhiteSpace($_)) {$_}}
        $EnvPathArray = $env:Path -split ";" | foreach {if (-not [System.String]::IsNullOrWhiteSpace($_)) {$_}}
        
        # => means that $EnvPathArray HAS the paths but $SystemPathArray DOES NOT
        # <= means that $SystemPathArray HAS the paths but $EnvPathArray DOES NOT
        $PathComparison = Compare-Object $SystemPathArray $EnvPathArray
        [System.Collections.ArrayList][Array]$SystemPathsThatWeWantToAddToEnvPath = $($PathComparison | Where-Object {$_.SideIndicator -eq "<="}).InputObject

        if ($SystemPathsThatWeWantToAddToEnvPath.Count -gt 0) {
            foreach ($NewPath in $SystemPathsThatWeWantToAddToEnvPath) {
                if ($env:Path[-1] -eq ";") {
                    $env:Path = "$env:Path$NewPath"
                }
                else {
                    $env:Path = "$env:Path;$NewPath"
                }
            }
        }
    }

    ##### END Native Helper Functions #####

    ##### BEGIN Variable/Parameter Transforms and PreRun Prep #####

    [Net.ServicePointManager]::SecurityProtocol = "tls12, tls11, tls"

    if (!$(GetElevation)) {
        Write-Error "The $($MyInvocation.MyCommand.Name) function must be ran from an elevated PowerShell Session (i.e. 'Run as Administrator')! Halting!"
        $global:FunctionResult = "1"
        return
    }

    # Need to make sure we are on Windows
    if (-not $($PSVersionTable.PSEdition -eq "Desktop" -or $PSVersionTable.Platform -eq "Win32NT")) {
        Write-Error "The $($MyInvocation.MyCommand.Name) function must only be used on Windows! Halting"
    }

    # Make sure use is not using both -UsePowerShellGet and -UseChocolateyCmdLine
    if ($UsePowerShellGet -and $UseChocolateyCmdLine) {
        Write-Error "Please only use either the -UsePowerShellGet switch or the -UseChocolateyCmdLine switch, not both. Halting!"
        return
    }

    if ($GetPenultimateVersion -and !$UsePowerShellGet) {
        Write-Error "The get -PenultimateVersion switch must be used with the -UsePowerShellGet switch. Halting!"
        return
    }

    if ($CommandName -match "\.exe") {
        $CommandName = $CommandName -replace "\.exe",""
    }
    $FinalCommandName = if ($CommandName) {$CommandName} else {$ProgramName}

    # Save the original System PATH and $env:Path before we do anything, just in case
    $OriginalSystemPath = $(Get-ItemProperty -Path 'Registry::HKEY_LOCAL_MACHINE\System\CurrentControlSet\Control\Session Manager\Environment' -Name PATH).Path
    $OriginalEnvPath = $env:Path
    Synchronize-SystemPathEnvPath

    try {
        if ($PSVersionTable.PSEdition -ne "Core") {
            $null = Install-PackageProvider -Name Nuget -Force -Confirm:$False
            $null = Set-PSRepository -Name PSGallery -InstallationPolicy Trusted

            # We're not going to attempt to use Chocolatey Resources with PSGet - it becomes a mess, so commenting out the below 2 lines
            #$null = Install-PackageProvider -Name Chocolatey -Force -Confirm:$False
            #$null = Set-PackageSource -Name chocolatey -Trusted -Force
        }
        else {
            $null = Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
        }
    }
    catch {
        Write-Error $_
        $global:FunctionResult = "1"
        return
    }

    # If a package provider is *not* specified or if -UseChocolateyCmdLine is explicitly specified, then we are just
    # going to use choco.exe because it is the most reliable method of getting things installed properly.
    if ($UseChocolateyCmdLine -or $(!$UsePowerShellGet -and !$UseChocolateyCmdLine)) {
        try {
            # NOTE: The Install-ChocolateyCmdLine function performs checks to see if Chocolatey is already installed, so don't worry about that
            $null = Install-ChocolateyCmdLine -ErrorAction Stop
        }
        catch {
            Write-Error "The Install-ChocolateyCmdLine function failed with the following error: $($_.Exception.Message)"
            return
        }

        try {
            if (![bool]$(Get-Command choco -ErrorAction SilentlyContinue)) {
                # The above install.ps1 probably already updated PATH, but it may not be updated in this particular PowerShell session
                # So, start a new PowerShell session and see if choco is available
                $ChocoCheck = Start-Job -Name ChocoPathTest -ScriptBlock {Get-Command choco} | Wait-Job | Receive-Job
        
                # $ChocoCheck.Source should return C:\ProgramData\chocolatey\bin\choco.exe
                if (!$ChocoCheck) {
                    try {
                        Write-Host "Refreshing `$env:Path..."
                        $null = Update-ChocolateyEnv -ErrorAction Stop
                    }
                    catch {
                        Write-Warning $_.Exception.Message
                        Write-Warning "Please start another PowerShell session in order to use the Chocolatey cmdline."
                    }
                }
        
                # If we STILL can't find choco.exe, then give up...
                if (![bool]$(Get-Command choco -ErrorAction SilentlyContinue)) {
                    Write-Error "Please start another PowerShell session in order to use the Chocolatey cmdline."
                    return
                }
            }
        }
        catch {
            Write-Error $_
            return
        }
    }

    try {
        $PackageManagerInstallObjects = Get-AllPackageInfo -ProgramName $ProgramName -ErrorAction SilentlyContinue
        [array]$ChocolateyInstalledProgramObjects = $PackageManagerInstallObjects.ChocolateyInstalledProgramObjects
        [array]$PSGetInstalledPackageObjects = $PackageManagerInstallObjects.PSGetInstalledPackageObjects
        [array]$RegistryProperties = $PackageManagerInstallObjects.RegistryProperties
        [array]$AppxInstalledPackageObjects = $PackageManagerInstallObjects.AppxAvailablePackages
    }
    catch {
        Write-Error $_
        return
    }

    # If PSGet says that a Program with a similar name is installed, get $PackageManagementCurrentVersion, $PackageManagementLatestVersion, and $PackageManagementPreviousVersion
    if ($PSGetInstalledPackageObjects.Count -eq 1) {
        $PackageManagementCurrentVersion = $PSGetInstalledPackageObjects
        $PackageManagementLatestVersion = $(Find-Package -Name $PSGetInstalledPackageObjects.Name -AllVersions | Sort-Object -Property Version -EA SilentlyContinue)[-1]
        $PackageManagementPreviousVersion = $(Find-Package -Name $PSGetInstalledPackageObjects.Name -AllVersions | Sort-Object -Property Version -EA SilentlyContinue)[-2]
    }
    if ($PSGetInstalledPackageObjects.Count -gt 1) {
        $ExactMatchCheck = $PSGetInstalledPackageObjects | Where-Object {$_.Name -eq $ProgramName}
        if (!$ExactMatchCheck) {
            Write-Warning "The following Programs are currently installed and match the string '$ProgramName':"
            for ($i=0; $i -lt $PSGetInstalledPackageObjects.Count; $i++) {
                Write-Host "$i) $($PSGetInstalledPackageObjects[$i].Name)"
            }
            $ValidChoiceNumbers = 0..$($PSGetInstalledPackageObjects.Count-1)
            $ProgramChoiceNumber = Read-Host -Prompt " Please choose the number that corresponds to the Program you would like to update:"
            while ($ValidChoiceNumbers -notcontains $ProgramChoiceNumber) {
                Write-Warning "'$ProgramChoiceNumber' is not a valid option. Please choose: $($ValidChoicenumbers -join ", ")"
                $ProgramChoiceNumber = Read-Host -Prompt " Please choose the number that corresponds to the Program you would like to update:"
            }

            $UpdatedProgramName = $PSGetInstalledPackageObjects[$ProgramChoiceNumber].Name
            $PackageManagementCurrentVersion = Get-Package -Name $UpdatedProgramName
            $PackageManagementLatestVersion = $(Find-Package -Name $UpdatedProgramName -AllVersions | Sort-Object -Property Version -EA SilentlyContinue)[-1]
            $PackageManagementPreviousVersion = $(Find-Package -Name $UpdatedProgramName -AllVersions | Sort-Object -Property Version -EA SilentlyContinue)[-2]
        }
        else {
            $PackageManagementCurrentVersion = Get-Package -Name $ProgramName
            $PackageManagementLatestVersion = $(Find-Package -Name $ProgramName -AllVersions | Sort-Object -Property Version)[-1]
            $PackageManagementPreviousVersion = $(Find-Package -Name $ProgramName -AllVersions | Sort-Object -Property Version -EA SilentlyContinue)[-2]
        }
    }

    # If Chocolatey says that a Program with a similar name is installed, get $ChocoCurrentVersion and $ChocoLatestVersion
    # Currently it's not possible to figure out $ChocoPreviousVersion reliably
    if ($ChocolateyInstalledProgramObjects.Count -gt 0) {
        if ($ChocolateyInstalledProgramObjects.Count -eq 1) {
            $ChocoCurrentVersion = $ChocolateyInstalledProgramObjects.Version
        }
        if ($ChocolateyInstalledProgramObjects.Count -gt 1) {
            $ExactMatchCheck = $ChocolateyInstalledProgramObjects | Where-Object {$_.ProgramName -eq $ProgramName}
            if (!$ExactMatchCheck) {
                Write-Warning "The following Programs are currently installed and match the string '$ProgramName':"
                for ($i=0; $i -lt $ChocolateyInstalledProgramObjects.Count; $i++) {
                    Write-Host "$i) $($ChocolateyInstalledProgramObjects[$i].ProgramName)"
                }
                $ValidChoiceNumbers = 0..$($ChocolateyInstalledProgramObjects.Count-1)
                $ProgramChoiceNumber = Read-Host -Prompt " Please choose the number that corresponds to the Program you would like to update:"
                while ($ValidChoiceNumbers -notcontains $ProgramChoiceNumber) {
                    Write-Warning "'$ProgramChoiceNumber' is not a valid option. Please choose: $($ValidChoicenumbers -join ", ")"
                    $ProgramChoiceNumber = Read-Host -Prompt " Please choose the number that corresponds to the Program you would like to update:"
                }

                $ProgramName = $ChocolateyInstalledProgramObjects[$ProgramChoiceNumber].ProgramName

                $ChocoCurrentVersion = $ChocolateyInstalledProgramObjects[$ProgramChoiceNumber].Version
            }
        }

        # Also get a list of outdated packages in case this Install-Program function is used to update a package
        $ChocolateyOutdatedProgramsPrep = choco outdated
        $UpperLineMatch = $ChocolateyOutdatedProgramsPrep -match "Output is package name"
        $LowerLineMatch = $ChocolateyOutdatedProgramsPrep -match "Chocolatey has determined"
        $UpperIndex = $ChocolateyOutdatedProgramsPrep.IndexOf($UpperLineMatch) + 2
        $LowerIndex = $ChocolateyOutdatedProgramsPrep.IndexOf($LowerLineMatch) - 2
        $ChocolateyOutdatedPrograms = $ChocolateyOutdatedProgramsPrep[$UpperIndex..$LowerIndex]

        [System.Collections.ArrayList]$ChocolateyOutdatedProgramsPSObjects = @()
        foreach ($line in $ChocolateyOutdatedPrograms) {
            $ParsedLine = $line -split "\|"
            $Program = $ParsedLine[0]
            $CurrentInstalledVersion = $ParsedLine[1]
            $LatestAvailableVersion = $ParsedLine[2]

            $PSObject = [pscustomobject]@{
                ProgramName                 = $Program
                CurrentInstalledVersion     = $CurrentInstalledVersion
                LatestAvailableVersion      = $LatestAvailableVersion
            }

            $null = $ChocolateyOutdatedProgramsPSObjects.Add($PSObject)
        }

        # Get all available Chocolatey Versions
        $AllChocoVersions = choco list $ProgramName -e --all

        # Get the latest version of $ProgramName from chocolatey
        $ChocoLatestVersion = $($AllChocoVersions[1] -split "[\s]")[1].Trim()

        # Also get the previous version of $ProgramName in case we want the previous version
        #$ChocoPreviousVersion = $($AllChocoVersions[2] -split "[\s]")[1].Trim()
    }

    ##### END Variable/Parameter Transforms and PreRun Prep #####


    ##### BEGIN Main Body #####

    $CheckLatestVersion = $(
        $PackageManagementCurrentVersion.Version -ne $PackageManagementLatestVersion.Version -or
        $ChocolateyOutdatedProgramsPSObjects.ProgramName -contains $ProgramName
    )
    $CheckPreviousVersion = $(
        $PackageManagementCurrentVersion.Version -ne $PackageManagementPreviousVersion.Version
    )
    if ($GetPenultimateVersion) {
        $VersionCheck = $CheckPreviousVersion
        $PackageManagementRequiredVersion = $PackageManagementPreviousVersion.Version
        $ChocoRequiredVersion = $ChocoLatestVersion
    }
    else {
        $VersionCheck = $CheckLatestVersion
        $PackageManagementRequiredVersion = $PackageManagementLatestVersion.Version
        $ChocoRequiredVersion = $ChocoLatestVersion
    }

    # Install $ProgramName if it's not already or if it's not the right/specified version...
    if ($($PSGetInstalledPackageObjects.Name -notcontains $ProgramName -and
    $ChocolateyInstalledProgramsPSObjects.ProgramName -notcontains $ProgramName) -or
    $VersionCheck -or $Force
    ) {
        $UsePSGetCheck = $($UsePowerShellGet -or $($PSGetInstalledPackageObjects.Name -contains $ProgramName -and $ChocolateyInstalledProgramsPSObjects.ProgramName -notcontains $ProgramName)) -and !$UseChocolateyCmdLine
        if ($UsePSGetCheck) {
            $PreInstallPackagesList = $(Get-Package).Name

            $InstallPackageSplatParams = @{
                Name            = $ProgramName
                Force           = $True
                ErrorAction     = "SilentlyContinue"
                ErrorVariable   = "InstallError"
                WarningAction   = "SilentlyContinue"
            }
            if ([bool]$PackageManagementRequiredVersion) {
                $InstallPackageSplatParams.Add("RequiredVersion",$PackageManagementRequiredVersion)
            }
            if ($PreRelease) {
                try {
                    $LatestVersion = $(Find-Package $ProgramName -AllVersions -ErrorAction Stop)[-1].Version
                    $InstallPackageSplatParams.Add("MinimumVersion",$LatestVersion)
                }
                catch {
                    Write-Verbose "Unable to find latest PreRelease version...Proceeding with 'Install-Package' without the '-MinimumVersion' parameter..."
                }
            }
            # NOTE: The PackageManagement install of $ProgramName is unreliable, so just in case, fallback to the Chocolatey cmdline for install
            $null = Install-Package @InstallPackageSplatParams
            if ($InstallError.Count -gt 0 -or $($(Get-Package).Name -match $ProgramName).Count -eq 0) {
                if ($($(Get-Package).Name -match $ProgramName).Count -gt 0) {
                    $null = Uninstall-Package $ProgramName -Force -ErrorAction SilentlyContinue
                }
                Write-Warning "There was a problem installing $ProgramName via PackageManagement/PowerShellGet!"
                
                if ($UsePowerShellGet) {
                    Write-Error "One or more errors occurred during the installation of $ProgramName via the the PackageManagement/PowerShellGet Modules failed! Installation has been rolled back! Halting!"
                    Write-Host "Errors for the Install-Package cmdlet are as follows:"
                    Write-Error $($InstallError | Out-String)
                    $global:FunctionResult = "1"
                    return
                }
                else {
                    Write-Host "Trying install via Chocolatey CmdLine..."
                    $PMInstall = $False
                }
            }
            else {
                $PMInstall = $True

                # Since Installation via PackageManagement/PowerShellGet was succesful, let's update $env:Path with the
                # latest from System PATH before we go nuts trying to find the main executable manually
                Synchronize-SystemPathEnvPath
                $env:Path = $($(Update-ChocolateyEnv -ErrorAction SilentlyContinue) -split ";" | foreach {
                    if (-not [System.String]::IsNullOrWhiteSpace($_) -and $(Test-Path $_ -ErrorAction SilentlyContinue)) {$_}
                }) -join ";"
            }
        }

        $UseChocoCheck = $(!$PMInstall -or $UseChocolateyCmdLine -or $ChocolateyInstalledProgramsPSObjects.ProgramName -contains $ProgramName) -and !$UsePowerShellGet
        if ($UseChocoCheck) {
            # Since choco installs can hang indefinitely, we're starting another powershell process and giving it a time limit
            try {
                if ($PreRelease) {
                    $CupArgs = "--pre -y"
                }
                elseif ([bool]$ChocoRequiredVersion) {
                    $CupArgs = "--version=$ChocoRequiredVersion -y"
                }
                else {
                    $CupArgs = "-y"
                }
                <#
                $ChocoPrepScript = @(
                    "`$ChocolateyResourceDirectories = Get-ChildItem -Path '$env:ProgramData\chocolatey\lib' -Directory | Where-Object {`$_.BaseName -match 'chocolatey'}"
                    '$ModulesToImport = foreach ($ChocoResourceDir in $ChocolateyResourceDirectories) {'
                    "    `$(Get-ChildItem -Path `$ChocoResourceDir.FullName -Recurse -Filter '*.psm1').FullName"
                    '}'
                    'foreach ($ChocoModulePath in $($ModulesToImport | Where-Object {$_})) {'
                    '    Import-Module $ChocoModulePath -Global'
                    '}'
                    "cup $ProgramName $CupArgs"
                )
                #>
                $ChocoPrepScript = $ChocoPrepScript -join "`n"
                $FinalArguments = "-NoProfile -NoLogo -Command `"cup $ProgramName $CupArgs`""
                
                $ProcessInfo = New-Object System.Diagnostics.ProcessStartInfo
                #$ProcessInfo.WorkingDirectory = $BinaryPath | Split-Path -Parent
                $ProcessInfo.FileName = $(Get-Command powershell).Source
                $ProcessInfo.RedirectStandardError = $true
                $ProcessInfo.RedirectStandardOutput = $true
                $ProcessInfo.UseShellExecute = $false
                $ProcessInfo.Arguments = $FinalArguments
                $Process = New-Object System.Diagnostics.Process
                $Process.StartInfo = $ProcessInfo
                $Process.Start() | Out-Null
                # Below $FinishedInAlottedTime returns boolean true/false
                # Give it 120 seconds to finish installing, otherwise, kill choco.exe
                $FinishedInAlottedTime = $Process.WaitForExit(120000)
                if (!$FinishedInAlottedTime) {
                    $Process.Kill()
                }
                $stdout = $Process.StandardOutput.ReadToEnd()
                $stderr = $Process.StandardError.ReadToEnd()
                $AllOutputA = $stdout + $stderr

                #$AllOutput | Export-CliXml "$HOME\CupInstallOutput.ps1"
                
                if (![bool]$($(clist --local-only $ProgramName) -match $ProgramName)) {
                    throw "'cup $ProgramName $CupArgs' failed with the following Output:`n$AllOutputA`n$AllOutputB"
                }

                # Since Installation via the Chocolatey CmdLine was succesful, let's update $env:Path with the
                # latest from System PATH before we go nuts trying to find the main executable manually
                Synchronize-SystemPathEnvPath
                $env:Path = Update-ChocolateyEnv -ErrorAction SilentlyContinue
            }
            catch {
                Write-Warning $_.Exception.Message

                Write-Host "Trying 'cup $ProgramName $CupArgs' within this powershell process ($PID)..." -ForegroundColor Yellow

                if (Get-Command cup -ErrorAction SilentlyContinue) {
                    cup $ProgramName -y
                }
                else {
                    Write-Warning "Please start a new PowerShell session and update Chocolatey via:`n    cup chocolatey -y"
                    Write-Error "'cup $ProgramName -y' failed! Halting!"
                    return
                }

                if (![bool]$($(clist --local-only $ProgramName) -match $ProgramName)) {
                    Write-Warning "Please start a new PowerShell session and update Chocolatey via:`n    cup chocolatey -y"
                    Write-Error "'cup $ProgramName -y' failed! Halting!"
                    return
                }
            }
        }
    }
    else {
        if ($ChocolateyInstalledProgramsPSObjects.ProgramName -contains $ProgramName) {
            Write-Warning "$ProgramName is already installed via the Chocolatey CmdLine!"
            $AlreadyInstalled = $True
        }
        elseif ([bool]$(Get-Package $ProgramName -ErrorAction SilentlyContinue)) {
            Write-Warning "$ProgramName is already installed via PackageManagement/PowerShellGet!"
            $AlreadyInstalled = $True
        }
    }

    ## BEGIN Try to Find Main Executable Post Install ##

    # Remove any conflicting Aliases
    if ($(Get-Command $FinalCommandName -ErrorAction SilentlyContinue).CommandType -eq "Alias") {
        while (Test-Path Alias:\$FinalCommandName -ErrorAction SilentlyContinue) {
            Remove-Item Alias:\$FinalCommandName
        }
    }
    
    # If we can't find the main executable...
    if (![bool]$(Get-Command $FinalCommandName -ErrorAction SilentlyContinue)) {
        # Try to find where the new .exe is by either using the user-provided $ExpectedInstallLocation or by comparing $OriginalSystemPath and $OriginalEnvPath to
        # the current PATH and $env:Path. THis is what the Get-ExePath function does

        $GetExePathSplatParams = @{
            GetProgramName          = $ProgramName
            OriginalSystemPath      = $OriginalSystemPath
            OriginalEnvPath         = $OriginalEnvPath
            FinalCommandName        = $FinalCommandName
        }
        if ($ExpectedInstallLocation) {
            if (Test-Path $ExpectedInstallLocation -ErrorAction SilentlyContinue) {
                $GetExePathSplatParams.Add('ExpectedInstallLocation',$ExpectedInstallLocation)
            }
        }

        [System.Collections.ArrayList][Array]$ExePath = Get-ExePath @GetExePathSplatParams

        if ($ExePath.Count -ge 1) {
            # Look for an exact match 
            if ([bool]$($ExePath -match "\\$FinalCommandName\.exe$")) {
                $FinalExeLocation = $ExePath -match "\\$FinalCommandName\.exe$"
            }
            else {
                $FinalExeLocation = $ExePath
            }
        }
    }

    # If we weren't able to find the main executable (or any potential main executables) for
    # $ProgramName, offer the option to scan the whole C:\ drive (with some obvious exceptions)
    if (![bool]$(Get-Command $FinalCommandName -ErrorAction SilentlyContinue) -and @($FinalExeLocation).Count -eq 0 -and $PSBoundParameters['ScanCommonInstallDirs']) {
        # Let's seach some common installation locations for directories that match $ProgramName

        $DirectoriesToSearch = @('C:\', $env:ProgramData, $env:ProgramFiles, ${env:ProgramFiles(x86)}, "$env:LocalAppData\Programs")

        [System.Collections.ArrayList]$ExePath = @()
        # Try to find a directory that matches the $ProgramName
        [System.Collections.ArrayList]$FoundMatchingDirs = @()
        foreach ($DirName in $DirectoriesToSearch) {
            $DirectoriesIndex = Get-ChildItem -Path $DirName -Directory
            foreach ($SubDirItem in $DirectoriesIndex) {
                if ($SubDirItem.Name -match $ProgramName) {
                    $null = $FoundMatchingDirs.Add($SubDirItem)
                }
            }
        }
        foreach ($MatchingDirItem in $FoundMatchingDirs) {
            $FilesIndex = Get-ChildItem -Path $MatchingDirItem.FullName -Recurse -File
            foreach ($FilePath in $FilesIndex.FullName) {
                if ($FilePath -match "(.*?)$FinalCommandName([^\\]+)") {
                    $null = $ExePath.Add($FilePath)
                }
            }
        }

        $FinalExeLocation = $ExePath
    }

    if (![bool]$(Get-Command $FinalCommandName -ErrorAction SilentlyContinue)) {
        Write-Host "The command '$FinalCommandName' is not currently available in PATH or env:Path, however, the following locations might contain the desired command:"
        @($FinalExeLocation) | foreach {Write-Host $_}

        Write-Host "Update System PATH and PowerShell $env:Path via:"
        Write-Host "Update-SystemPathNow -PathToAdd <PathToDirectoryContainingCommand>"
    }

    if ($UseChocoCheck) {
        $InstallManager = "choco.exe"
        $InstallCheck = $(clist --local-only $ProgramName)[1]
    }
    if ($PMInstall -or [bool]$(Get-Package $ProgramName -ErrorAction SilentlyContinue)) {
        $InstallManager = "PowerShellGet"
        $InstallCheck = Get-Package $ProgramName -ErrorAction SilentlyContinue
    }

    if ($AlreadyInstalled) {
        $InstallAction = "AlreadyInstalled"
    }
    elseif (!$AlreadyInstalled -and $VersionCheck) {
        $InstallAction = "Updated"
    }
    else {
        $InstallAction = "FreshInstall"
    }

    if ($InstallAction -match "Updated|FreshInstall") {
        Write-Host "The program '$ProgramName' was installed successfully!" -ForegroundColor Green
    }
    elseif ($InstallAction -eq "AlreadyInstalled") {
        Write-Host "The program '$ProgramName' is already installed!" -ForegroundColor Green
    }

    $OutputHT = [ordered]@{
        InstallManager      = $InstallManager
        InstallAction       = $InstallAction
        InstallCheck        = $InstallCheck
    }
    if ([array]$($FinalExeLocation).Count -gt 1) {
        $OutputHT.Add("PossibleMainExecutables",$FinalExeLocation)
    }
    else {
        $OutputHT.Add("MainExecutable",$FinalExeLocation)
    }
    $OutputHT.Add("OriginalSystemPath",$OriginalSystemPath)
    $OutputHT.Add("CurrentSystemPath",$(Get-ItemProperty -Path 'Registry::HKEY_LOCAL_MACHINE\System\CurrentControlSet\Control\Session Manager\Environment' -Name PATH).Path)
    $OutputHT.Add("OriginalEnvPath",$OriginalEnvPath)
    $OutputHT.Add("CurrentEnvPath",$env:Path)
    
    [pscustomobject]$OutputHT

    ##### END Main Body #####
}


<#
    .SYNOPSIS
        The New-Runspace function creates a Runspace that executes the specified ScriptBlock in the background
        and posts results to a Global Variable called $global:RSSyncHash.

    .DESCRIPTION
        See .SYNOPSIS

    .NOTES

    .PARAMETER RunspaceName
        This parameter is MANDATORY.

        This parameter takes a string that represents the name of the new Runspace that you are creating. The name
        is represented as a key in the $global:RSSyncHash variable called: <RunspaceName>Result

    .PARAMETER ScriptBlock
        This parameter is MANDATORY.

        This parameter takes a scriptblock that will be executed in the new Runspace.

    .PARAMETER MirrorCurrentEnv
        This parameter is OPTIONAL, however, it is set to $True by default.

        This parameter is a switch. If used, all variables, functions, and Modules that are loaded in your
        current scope will be forwarded to the new Runspace.

        You can prevent the New-Runspace function from automatically mirroring your current environment by using
        this switch like: -MirrorCurrentEnv:$False 

    .PARAMETER Wait
        This parameter is OPTIONAL.

        This parameter is a switch. If used, the main PowerShell thread will wait for the Runsapce to return
        output before proceeeding.

    .EXAMPLE
        # Open a PowerShell Session, source the function, and -

        PS C:\Users\zeroadmin> $GetProcessResults = Get-Process

        # In the below, Runspace1 refers to your current interactive PowerShell Session...

        PS C:\Users\zeroadmin> Get-Runspace

        Id Name            ComputerName    Type          State         Availability
        -- ----            ------------    ----          -----         ------------
        1 Runspace1       localhost       Local         Opened        Busy

        # The below will create a 'Runspace Manager Runspace' (if it doesn't already exist)
        # to manage all other new Runspaces created by the New-Runspace function.
        # Additionally, it will create the Runspace that actually runs the -ScriptBlock.
        # The 'Runspace Manager Runspace' disposes of new Runspaces when they're
        # finished running.

        PS C:\Users\zeroadmin> New-RunSpace -RunSpaceName PSIds -ScriptBlock {$($GetProcessResults | Where-Object {$_.Name -eq "powershell"}).Id}

        # The 'Runspace Manager Runspace' persists just in case you create any additional
        # Runspaces, but the Runspace that actually ran the above -ScriptBlock does not.
        # In the below, 'Runspace2' is the 'Runspace Manager Runspace. 

        PS C:\Users\zeroadmin> Get-Runspace

        Id Name            ComputerName    Type          State         Availability
        -- ----            ------------    ----          -----         ------------
        1 Runspace1       localhost       Local         Opened        Busy
        2 Runspace2       localhost       Local         Opened        Busy

        # You can actively identify (as opposed to infer) the 'Runspace Manager Runspace'
        # by using one of three Global variables created by the New-Runspace function:

        PS C:\Users\zeroadmin> $global:RSJobCleanup.PowerShell.Runspace

        Id Name            ComputerName    Type          State         Availability
        -- ----            ------------    ----          -----         ------------
        2 Runspace2       localhost       Local         Opened        Busy

        # As mentioned above, the New-RunspaceName function creates three Global
        # Variables. They are $global:RSJobs, $global:RSJobCleanup, and
        # $global:RSSyncHash. Your output can be found in $global:RSSyncHash.

        PS C:\Users\zeroadmin> $global:RSSyncHash

        Name                           Value
        ----                           -----
        PSIdsResult                    @{Done=True; Errors=; Output=System.Object[]}
        ProcessedJobRecords            {@{Name=PSIdsHelper; PSInstance=System.Management.Automation.PowerShell; Runspace=System.Management.Automation.Runspaces.Loca...


        PS C:\Users\zeroadmin> $global:RSSyncHash.PSIdsResult

        Done Errors Output
        ---- ------ ------
        True        {1300, 2728, 2960, 3712...}


        PS C:\Users\zeroadmin> $global:RSSyncHash.PSIdsResult.Output
        1300
        2728
        2960
        3712
        4632

        # Important Note: You don't need to worry about passing variables / functions /
        # Modules to the Runspace. Everything in your current session/scope is
        # automatically forwarded by the New-Runspace function:

        PS C:\Users\zeroadmin> function Test-Func {'This is Test-Func output'}
        PS C:\Users\zeroadmin> New-RunSpace -RunSpaceName FuncTest -ScriptBlock {Test-Func}
        PS C:\Users\zeroadmin> $global:RSSyncHash

        Name                           Value
        ----                           -----
        FuncTestResult                 @{Done=True; Errors=; Output=This is Test-Func output}
        PSIdsResult                    @{Done=True; Errors=; Output=System.Object[]}
        ProcessedJobRecords            {@{Name=PSIdsHelper; PSInstance=System.Management.Automation.PowerShell; Runspace=System.Management.Automation.Runspaces.Loca...

        PS C:\Users\zeroadmin> $global:RSSyncHash.FuncTestResult.Output
        This is Test-Func output  
#>
function New-RunSpace {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory=$True)]
        [string]$RunspaceName,

        [Parameter(Mandatory=$True)]
        [scriptblock]$ScriptBlock,

        [Parameter(Mandatory=$False)]
        [switch]$MirrorCurrentEnv = $True,

        [Parameter(Mandatory=$False)]
        [switch]$Wait
    )

    #region >> Helper Functions

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

    #endregion >> Helper Functions

    #region >> Runspace Prep

    # Create Global Variable Names that don't conflict with other exisiting Global Variables
    $ExistingGlobalVariables = Get-Variable -Scope Global
    $DesiredGlobalVariables = @("RSSyncHash","RSJobCleanup","RSJobs")
    if ($ExistingGlobalVariables.Name -notcontains 'RSSyncHash') {
        $GlobalRSSyncHashName = NewUniqueString -PossibleNewUniqueString "RSSyncHash" -ArrayOfStrings $ExistingGlobalVariables.Name
        Invoke-Expression "`$global:$GlobalRSSyncHashName = [hashtable]::Synchronized(@{})"
        $globalRSSyncHash = Get-Variable -Name $GlobalRSSyncHashName -Scope Global -ValueOnly
    }
    else {
        $GlobalRSSyncHashName = 'RSSyncHash'

        # Also make sure that $RunSpaceName is a unique key in $global:RSSyncHash
        if ($RSSyncHash.Keys -contains $RunSpaceName) {
            $RSNameOriginal = $RunSpaceName
            $RunSpaceName = NewUniqueString -PossibleNewUniqueString $RunSpaceName -ArrayOfStrings $RSSyncHash.Keys
            if ($RSNameOriginal -ne $RunSpaceName) {
                Write-Warning "The RunspaceName '$RSNameOriginal' already exists. Your new RunspaceName will be '$RunSpaceName'"
            }
        }

        $globalRSSyncHash = $global:RSSyncHash
    }
    if ($ExistingGlobalVariables.Name -notcontains 'RSJobCleanup') {
        $GlobalRSJobCleanupName = NewUniqueString -PossibleNewUniqueString "RSJobCleanup" -ArrayOfStrings $ExistingGlobalVariables.Name
        Invoke-Expression "`$global:$GlobalRSJobCleanupName = [hashtable]::Synchronized(@{})"
        $globalRSJobCleanup = Get-Variable -Name $GlobalRSJobCleanupName -Scope Global -ValueOnly
    }
    else {
        $GlobalRSJobCleanupName = 'RSJobCleanup'
        $globalRSJobCleanup = $global:RSJobCleanup
    }
    if ($ExistingGlobalVariables.Name -notcontains 'RSJobs') {
        $GlobalRSJobsName = NewUniqueString -PossibleNewUniqueString "RSJobs" -ArrayOfStrings $ExistingGlobalVariables.Name
        Invoke-Expression "`$global:$GlobalRSJobsName = [System.Collections.ArrayList]::Synchronized([System.Collections.ArrayList]::new())"
        $globalRSJobs = Get-Variable -Name $GlobalRSJobsName -Scope Global -ValueOnly
    }
    else {
        $GlobalRSJobsName = 'RSJobs'
        $globalRSJobs = $global:RSJobs
    }
    $GlobalVariables = @($GlobalSyncHashName,$GlobalRSJobCleanupName,$GlobalRSJobsName)
    #Write-Host "Global Variable names are: $($GlobalVariables -join ", ")"

    # Prep an empty pscustomobject for the RunspaceNameResult Key in $globalRSSyncHash
    $globalRSSyncHash."$RunspaceName`Result" = [pscustomobject]@{}

    #endregion >> Runspace Prep


    ##### BEGIN Runspace Manager Runspace (A Runspace to Manage All Runspaces) #####

    $globalRSJobCleanup.Flag = $True

    if ($ExistingGlobalVariables.Name -notcontains 'RSJobCleanup') {
        #Write-Host '$global:RSJobCleanup does NOT already exists. Creating New Runspace Manager Runspace...'
        $RunspaceMgrRunspace = [runspacefactory]::CreateRunspace()
        if ($PSVersionTable.PSEdition -ne "Core") {
            $RunspaceMgrRunspace.ApartmentState = "STA"
        }
        $RunspaceMgrRunspace.ThreadOptions = "ReuseThread"
        $RunspaceMgrRunspace.Open()

        # Prepare to Receive the Child Runspace Info to the RunspaceManagerRunspace
        $RunspaceMgrRunspace.SessionStateProxy.SetVariable("JobCleanup",$globalRSJobCleanup)
        $RunspaceMgrRunspace.SessionStateProxy.SetVariable("jobs",$globalRSJobs)
        $RunspaceMgrRunspace.SessionStateProxy.SetVariable("SyncHash",$globalRSSyncHash)

        $globalRSJobCleanup.PowerShell = [PowerShell]::Create().AddScript({

            ##### BEGIN Runspace Manager Runspace Helper Functions #####

            # Load the functions we packed up
            $FunctionsForSBUse | foreach { Invoke-Expression $_ }

            ##### END Runspace Manager Runspace Helper Functions #####

            # Routine to handle completed Runspaces
            $ProcessedJobRecords = [System.Collections.ArrayList]::new()
            $SyncHash.ProcessedJobRecords = $ProcessedJobRecords
            while ($JobCleanup.Flag) {
                if ($jobs.Count -gt 0) {
                    $Counter = 0
                    foreach($job in $jobs) { 
                        if ($ProcessedJobRecords.Runspace.InstanceId.Guid -notcontains $job.Runspace.InstanceId.Guid) {
                            $job | Export-CliXml "$HOME\job$Counter.xml" -Force
                            $CollectJobRecordPrep = Import-CliXML -Path "$HOME\job$Counter.xml"
                            Remove-Item -Path "$HOME\job$Counter.xml" -Force
                            $null = $ProcessedJobRecords.Add($CollectJobRecordPrep)
                        }

                        if ($job.AsyncHandle.IsCompleted -or $job.AsyncHandle -eq $null) {
                            [void]$job.PSInstance.EndInvoke($job.AsyncHandle)
                            $job.Runspace.Dispose()
                            $job.PSInstance.Dispose()
                            $job.AsyncHandle = $null
                            $job.PSInstance = $null
                        }
                        $Counter++
                    }

                    # Determine if we can have the Runspace Manager Runspace rest
                    $temparray = $jobs.clone()
                    $temparray | Where-Object {
                        $_.AsyncHandle.IsCompleted -or $_.AsyncHandle -eq $null
                    } | foreach {
                        $temparray.remove($_)
                    }

                    <#
                    if ($temparray.Count -eq 0 -or $temparray.AsyncHandle.IsCompleted -notcontains $False) {
                        $JobCleanup.Flag = $False
                    }
                    #>

                    Start-Sleep -Seconds 5

                    # Optional -
                    # For realtime updates to a GUI depending on changes in data within the $globalRSSyncHash, use
                    # a something like the following (replace with $RSSyncHash properties germane to your project)
                    <#
                    if ($RSSyncHash.WPFInfoDatagrid.Items.Count -ne 0 -and $($RSSynchash.IPArray.Count -ne 0 -or $RSSynchash.IPArray -ne $null)) {
                        if ($RSSyncHash.WPFInfoDatagrid.Items.Count -ge $RSSynchash.IPArray.Count) {
                            Update-Window -Control $RSSyncHash.WPFInfoPleaseWaitLabel -Property Visibility -Value "Hidden"
                        }
                    }
                    #>
                }
            } 
        })

        # Start the RunspaceManagerRunspace
        $globalRSJobCleanup.PowerShell.Runspace = $RunspaceMgrRunspace
        $globalRSJobCleanup.Thread = $globalRSJobCleanup.PowerShell.BeginInvoke()
    }

    ##### END Runspace Manager Runspace #####


    ##### BEGIN New Generic Runspace #####

    $GenericRunspace = [runspacefactory]::CreateRunspace()
    if ($PSVersionTable.PSEdition -ne "Core") {
        $GenericRunspace.ApartmentState = "STA"
    }
    $GenericRunspace.ThreadOptions = "ReuseThread"
    $GenericRunspace.Open()

    # Pass the $globalRSSyncHash to the Generic Runspace so it can read/write properties to it and potentially
    # coordinate with other runspaces
    $GenericRunspace.SessionStateProxy.SetVariable("SyncHash",$globalRSSyncHash)

    # Pass $globalRSJobCleanup and $globalRSJobs to the Generic Runspace so that the Runspace Manager Runspace can manage it
    $GenericRunspace.SessionStateProxy.SetVariable("JobCleanup",$globalRSJobCleanup)
    $GenericRunspace.SessionStateProxy.SetVariable("Jobs",$globalRSJobs)
    $GenericRunspace.SessionStateProxy.SetVariable("ScriptBlock",$ScriptBlock)

    # Pass all other notable environment characteristics 
    if ($MirrorCurrentEnv) {
        [System.Collections.ArrayList]$SetEnvStringArray = @()

        $VariablesNotToForward = @('globalRSSyncHash','RSSyncHash','globalRSJobCleanUp','RSJobCleanup',
        'globalRSJobs','RSJobs','ExistingGlobalVariables','DesiredGlobalVariables','$GlobalRSSyncHashName',
        'RSNameOriginal','GlobalRSJobCleanupName','GlobalRSJobsName','GlobalVariables','RunspaceMgrRunspace',
        'GenericRunspace','ScriptBlock')

        $Variables = Get-Variable
        foreach ($VarObj in $Variables) {
            if ($VariablesNotToForward -notcontains $VarObj.Name) {
                try {
                    $GenericRunspace.SessionStateProxy.SetVariable($VarObj.Name,$VarObj.Value)
                }
                catch {
                    Write-Verbose "Skipping `$$($VarObj.Name)..."
                }
            }
        }

        # Set Environment Variables
        $EnvVariables = Get-ChildItem Env:\
        if ($PSBoundParameters['EnvironmentVariablesToForward'] -and $EnvironmentVariablesToForward -notcontains '*') {
            $EnvVariables = foreach ($VarObj in $EnvVariables) {
                if ($EnvironmentVariablesToForward -contains $VarObj.Name) {
                    $VarObj
                }
            }
        }
        $SetEnvVarsPrep = foreach ($VarObj in $EnvVariables) {
            if ([char[]]$VarObj.Name -contains '(' -or [char[]]$VarObj.Name -contains ' ') {
                $EnvStringArr = @(
                    'try {'
                    $('    ${env:' + $VarObj.Name + '} = ' + "@'`n$($VarObj.Value)`n'@")
                    '}'
                    'catch {'
                    "    Write-Verbose 'Unable to forward environment variable $($VarObj.Name)'"
                    '}'
                )
            }
            else {
                $EnvStringArr = @(
                    'try {'
                    $('    $env:' + $VarObj.Name + ' = ' + "@'`n$($VarObj.Value)`n'@")
                    '}'
                    'catch {'
                    "    Write-Verbose 'Unable to forward environment variable $($VarObj.Name)'"
                    '}'
                )
            }
            $EnvStringArr -join "`n"
        }
        $SetEnvVarsString = $SetEnvVarsPrep -join "`n"

        $null = $SetEnvStringArray.Add($SetEnvVarsString)

        # Set Modules
        $Modules = Get-Module
        if ($PSBoundParameters['ModulesToForward'] -and $ModulesToForward -notcontains '*') {
            $Modules = foreach ($ModObj in $Modules) {
                if ($ModulesToForward -contains $ModObj.Name) {
                    $ModObj
                }
            }
        }

        $ModulesNotToForward = @('MiniLab')

        $SetModulesPrep = foreach ($ModObj in $Modules) {
            if ($ModulesNotToForward -notcontains $ModObj.Name) {
                $ModuleManifestFullPath = $(Get-ChildItem -Path $ModObj.ModuleBase -Recurse -File | Where-Object {
                    $_.Name -eq "$($ModObj.Name).psd1"
                }).FullName

                $ModStringArray = @(
                    '$tempfile = [IO.Path]::Combine([IO.Path]::GetTempPath(), [IO.Path]::GetRandomFileName())'
                    "if (![bool]('$($ModObj.Name)' -match '\.WinModule')) {"
                    '    try {'
                    "        Import-Module '$($ModObj.Name)' -NoClobber -ErrorAction Stop 2>`$tempfile"
                    '    }'
                    '    catch {'
                    '        try {'
                    "            Import-Module '$ModuleManifestFullPath' -NoClobber -ErrorAction Stop 2>`$tempfile"
                    '        }'
                    '        catch {'
                    "            Write-Warning 'Unable to Import-Module $($ModObj.Name)'"
                    '        }'
                    '    }'
                    '}'
                    'if (Test-Path $tempfile) {'
                    '    Remove-Item $tempfile -Force'
                    '}'
                )
                $ModStringArray -join "`n"
            }
        }
        $SetModulesString = $SetModulesPrep -join "`n"

        $null = $SetEnvStringArray.Add($SetModulesString)
    
        # Set Functions
        $Functions = Get-ChildItem Function:\ | Where-Object {![System.String]::IsNullOrWhiteSpace($_.Name)}
        if ($PSBoundParameters['FunctionsToForward'] -and $FunctionsToForward -notcontains '*') {
            $Functions = foreach ($FuncObj in $Functions) {
                if ($FunctionsToForward -contains $FuncObj.Name) {
                    $FuncObj
                }
            }
        }
        $SetFunctionsPrep = foreach ($FuncObj in $Functions) {
            $FunctionText = Invoke-Expression $('@(${Function:' + $FuncObj.Name + '}.Ast.Extent.Text)')
            if ($($FunctionText -split "`n").Count -gt 1) {
                if ($($FunctionText -split "`n")[0] -match "^function ") {
                    if ($($FunctionText -split "`n") -match "^'@") {
                        Write-Warning "Unable to forward function $($FuncObj.Name) due to heredoc string: '@"
                    }
                    else {
                        'Invoke-Expression ' + "@'`n$FunctionText`n'@"
                    }
                }
            }
            elseif ($($FunctionText -split "`n").Count -eq 1) {
                if ($FunctionText -match "^function ") {
                    'Invoke-Expression ' + "@'`n$FunctionText`n'@"
                }
            }
        }
        $SetFunctionsString = $SetFunctionsPrep -join "`n"

        $null = $SetEnvStringArray.Add($SetFunctionsString)

        $GenericRunspace.SessionStateProxy.SetVariable("SetEnvStringArray",$SetEnvStringArray)
    }

    $GenericPSInstance = [powershell]::Create()

    # Define the main PowerShell Script that will run the $ScriptBlock
    $null = $GenericPSInstance.AddScript({
        $SyncHash."$RunSpaceName`Result" | Add-Member -Type NoteProperty -Name Done -Value $False
        $SyncHash."$RunSpaceName`Result" | Add-Member -Type NoteProperty -Name Errors -Value $null
        $SyncHash."$RunSpaceName`Result" | Add-Member -Type NoteProperty -Name ErrorsDetailed -Value $null
        $SyncHash."$RunspaceName`Result".Errors = [System.Collections.ArrayList]::new()
        $SyncHash."$RunspaceName`Result".ErrorsDetailed = [System.Collections.ArrayList]::new()
        $SyncHash."$RunspaceName`Result" | Add-Member -Type NoteProperty -Name ThisRunspace -Value $($(Get-Runspace)[-1])
        [System.Collections.ArrayList]$LiveOutput = @()
        $SyncHash."$RunspaceName`Result" | Add-Member -Type NoteProperty -Name LiveOutput -Value $LiveOutput
        

        
        ##### BEGIN Generic Runspace Helper Functions #####

        # Load the environment we packed up
        if ($SetEnvStringArray) {
            foreach ($obj in $SetEnvStringArray) {
                if (![string]::IsNullOrWhiteSpace($obj)) {
                    try {
                        Invoke-Expression $obj
                    }
                    catch {
                        $null = $SyncHash."$RunSpaceName`Result".Errors.Add($_)

                        $ErrMsg = "Problem with:`n$obj`nError Message:`n" + $($_ | Out-String)
                        $null = $SyncHash."$RunSpaceName`Result".ErrorsDetailed.Add($ErrMsg)
                    }
                }
            }
        }

        ##### END Generic Runspace Helper Functions #####

        ##### BEGIN Script To Run #####

        try {
            # NOTE: Depending on the content of the scriptblock, InvokeReturnAsIs() and Invoke-Command can cause
            # the Runspace to hang. Invoke-Expression works all the time.
            #$Result = $ScriptBlock.InvokeReturnAsIs()
            #$Result = Invoke-Command -ScriptBlock $ScriptBlock
            #$SyncHash."$RunSpaceName`Result" | Add-Member -Type NoteProperty -Name SBString -Value $ScriptBlock.ToString()
            $Result = Invoke-Expression -Command $ScriptBlock.ToString()
            $SyncHash."$RunSpaceName`Result" | Add-Member -Type NoteProperty -Name Output -Value $Result
        }
        catch {
            $SyncHash."$RunSpaceName`Result" | Add-Member -Type NoteProperty -Name Output -Value $Result

            $null = $SyncHash."$RunSpaceName`Result".Errors.Add($_)

            $ErrMsg = "Problem with:`n$($ScriptBlock.ToString())`nError Message:`n" + $($_ | Out-String)
            $null = $SyncHash."$RunSpaceName`Result".ErrorsDetailed.Add($ErrMsg)
        }

        ##### END Script To Run #####

        $SyncHash."$RunSpaceName`Result".Done = $True
    })

    # Start the Generic Runspace
    $GenericPSInstance.Runspace = $GenericRunspace

    if ($Wait) {
        # The below will make any output of $GenericRunspace available in $Object in current scope
        $Object = New-Object 'System.Management.Automation.PSDataCollection[psobject]'
        $GenericAsyncHandle = $GenericPSInstance.BeginInvoke($Object,$Object)

        $GenericRunspaceInfo = [pscustomobject]@{
            Name            = $RunSpaceName + "Generic"
            PSInstance      = $GenericPSInstance
            Runspace        = $GenericRunspace
            AsyncHandle     = $GenericAsyncHandle
        }
        $null = $globalRSJobs.Add($GenericRunspaceInfo)

        #while ($globalRSSyncHash."$RunSpaceName`Done" -ne $True) {
        while ($GenericAsyncHandle.IsCompleted -ne $True) {
            #Write-Host "Waiting for -ScriptBlock to finish..."
            Start-Sleep -Milliseconds 10
        }

        $globalRSSyncHash."$RunspaceName`Result".Output
        #$Object
    }
    else {
        $HelperRunspace = [runspacefactory]::CreateRunspace()
        if ($PSVersionTable.PSEdition -ne "Core") {
            $HelperRunspace.ApartmentState = "STA"
        }
        $HelperRunspace.ThreadOptions = "ReuseThread"
        $HelperRunspace.Open()

        # Pass the $globalRSSyncHash to the Helper Runspace so it can read/write properties to it and potentially
        # coordinate with other runspaces
        $HelperRunspace.SessionStateProxy.SetVariable("SyncHash",$globalRSSyncHash)

        # Pass $globalRSJobCleanup and $globalRSJobs to the Helper Runspace so that the Runspace Manager Runspace can manage it
        $HelperRunspace.SessionStateProxy.SetVariable("JobCleanup",$globalRSJobCleanup)
        $HelperRunspace.SessionStateProxy.SetVariable("Jobs",$globalRSJobs)

        # Set any other needed variables in the $HelperRunspace
        $HelperRunspace.SessionStateProxy.SetVariable("GenericRunspace",$GenericRunspace)
        $HelperRunspace.SessionStateProxy.SetVariable("GenericPSInstance",$GenericPSInstance)
        $HelperRunspace.SessionStateProxy.SetVariable("RunSpaceName",$RunSpaceName)

        $HelperPSInstance = [powershell]::Create()

        # Define the main PowerShell Script that will run the $ScriptBlock
        $null = $HelperPSInstance.AddScript({
            ##### BEGIN Script To Run #####

            # The below will make any output of $GenericRunspace available in $Object in current scope
            $Object = New-Object 'System.Management.Automation.PSDataCollection[psobject]'
            $GenericAsyncHandle = $GenericPSInstance.BeginInvoke($Object,$Object)

            $GenericRunspaceInfo = [pscustomobject]@{
                Name            = $RunSpaceName + "Generic"
                PSInstance      = $GenericPSInstance
                Runspace        = $GenericRunspace
                AsyncHandle     = $GenericAsyncHandle
            }
            $null = $Jobs.Add($GenericRunspaceInfo)

            #while ($SyncHash."$RunSpaceName`Done" -ne $True) {
            while ($GenericAsyncHandle.IsCompleted -ne $True) {
                #Write-Host "Waiting for -ScriptBlock to finish..."
                Start-Sleep -Milliseconds 10
            }

            ##### END Script To Run #####
        })

        # Start the Helper Runspace
        $HelperPSInstance.Runspace = $HelperRunspace
        $HelperAsyncHandle = $HelperPSInstance.BeginInvoke()

        $HelperRunspaceInfo = [pscustomobject]@{
            Name            = $RunSpaceName + "Helper"
            PSInstance      = $HelperPSInstance
            Runspace        = $HelperRunspace
            AsyncHandle     = $HelperAsyncHandle
        }
        $null = $globalRSJobs.Add($HelperRunspaceInfo)
    }

    ##### END Generic Runspace
}


<#
    .SYNOPSIS
        Uninstalls the specified Program. The value provided to the -ProgramName parameter does NOT have
        to be an exact match. If multiple matches are found, the function prompts for a specific selection
        (one of which is 'all of the above').

    .DESCRIPTION
        See .SYNOPSIS

    .NOTES

    .PARAMETER ProgramName
        This parameter is MANDATORY.

        This parameter takes a string that represents the name of the program you would like to uninstall. The
        value provided to this parameter does not have to be an exact match. If multiple matches are found the
        function prompts for a specfic selection (one of which is 'all of the above').

    .PARAMETER UninstallAllSimilarlyNamedPackages
        This parameter is OPTIONAL.

        This parameter is a switch. If used, all programs that match the string provided to the -ProgramName
        parameter will be uninstalled. The user will NOT receive a prompt for specific selection.

    .EXAMPLE
        # Open an elevated PowerShell Session, import the module, and -

        PS C:\Users\zeroadmin> Uninstall-Program -ProgramName python

    .EXAMPLE
        # Open an elevated PowerShell Session, import the module, and -
        
        PS C:\Users\zeroadmin> Uninstall-Program -ProgramName python -UninstallAllSimilarlyNamedPackages

#>
function Uninstall-Program {
    [CmdletBinding()]
    Param (
        [Parameter(
            Mandatory=$True,
            Position=0
        )]
        [string]$ProgramName,

        [Parameter(Mandatory=$False)]
        [switch]$UninstallAllSimilarlyNamedPackages
    )

    #region >> Variable/Parameter Transforms and PreRun Prep

    if (!$(GetElevation)) {
        Write-Error "The $($MyInvocation.MyCommand.Name) function must be ran from an elevated PowerShell Session (i.e. 'Run as Administrator')! Halting!"
        $global:FunctionResult = "1"
        return
    }

    try {
        $PackageManagerInstallObjects = Get-AllPackageInfo -ProgramName $ProgramName -ErrorAction SilentlyContinue
        [array]$ChocolateyInstalledProgramObjects = $PackageManagerInstallObjects.ChocolateyInstalledProgramObjects
        [array]$PSGetInstalledPackageObjects = $PackageManagerInstallObjects.PSGetInstalledPackageObjects
        [array]$RegistryProperties = $PackageManagerInstallObjects.RegistryProperties
        [array]$AppxInstalledPackageObjects = $PackageManagerInstallObjects.AppxAvailablePackages
    }
    catch {
        Write-Error $_
        $global:FunctionResult = "1"
        return
    }

    #endregion >> Variable/Parameter Transforms and PreRun Prep
    

    #region >> Main Body
    if ($ChocolateyInstalledProgramObjects.Count -eq 0 -and $PSGetInstalledPackageObjects.Count -eq 0 -and $RegistryProperties.Count -eq 0) {
        Write-Error "Unable to find an installed program matching the name $ProgramName! Halting!"
        $global:FunctionResult = "1"
        return
    }

    # If we found an install that was handled by PSGet, then uninstall via PSGet
    [System.Collections.ArrayList]$PSGetUninstallFailures = @()
    if ($PSGetInstalledPackageObjects.Count -gt 0) {
        if ($PSGetInstalledPackageObjects.Count -gt 1 -and !$UninstallAllSimilarlyNamedPackages) {
            Write-Warning "Multiple packages matching the name '$ProgramName' have been found via searching PSGet."

            for ($i=0; $i -lt $PSGetInstalledPackageObjects.Count; $i++) {
                Write-Host "$i) $($PSGetInstalledPackageObjects[$i].Name)"
            }
            Write-Host "$($PSGetInstalledPackageObjects.Count)) All of the Above"

            [int[]]$ValidChoiceNumbers = 0..$($PSGetInstalledPackageObjects.Count)
            $UninstallChoice = Read-Host -Prompt "Please enter one or more numbers (separated by commas) that correspond to the program(s) you would like to uninstall."
            if ($UninstallChoice -match ',') {
                [array]$UninstallChoiceArray = $($UninstallChoice -split ',').Trim()
            }
            else {
                [array]$UninstallChoiceArray = $UninstallChoice
            }

            [System.Collections.ArrayList]$InvalidChoices = @()
            foreach ($ChoiceNumber in $UninstallChoiceArray) {
                if ($ValidChoiceNumbers -notcontains $ChoiceNumber) {
                    $null = $InvalidChoices.Add($ChoiceNumber)
                }
            }

            while ($InvalidChoices.Count -ne 0) {
                Write-Warning "The following selections are NOT valid Choice Numbers: $($InvalidChoices -join ', ')"

                $UninstallChoice = Read-Host -Prompt "Please enter one or more numbers (separated by commas) that correspond to the program(s) you would like to uninstall."
                if ($UninstallChoice -match ',') {
                    [array]$UninstallChoiceArray = $($UninstallChoice -split ',').Trim()
                }
                else {
                    [array]$UninstallChoiceArray = $UninstallChoice
                }

                [System.Collections.ArrayList]$InvalidChoices = @()
                foreach ($ChoiceNumber in $UninstallChoiceArray) {
                    if ($ValidChoiceNumbers -notcontains $ChoiceNumber) {
                        $null = $InvalidChoices.Add($ChoiceNumber)
                    }
                }
            }

            # Make sure that $UninstallChoiceArray is an integer array sorted 0..N
            try {
                [int[]]$UninstallChoiceArray = $UninstallChoiceArray | Sort-Object
            }
            catch {
                Write-Error $_
                Write-Error "`$UninstallChoiceArray cannot be converted to an array of integers! Halting!"
                $global:FunctionResult = "1"
                return
            }

            if ($UninstallChoiceArray -notcontains $PSGetInstalledPackageObjects.Count) {
                [array]$FinalPackagesSelectedForUninstall = foreach ($ChoiceNumber in $UninstallChoiceArray) {
                    $PSGetInstalledPackageObjects[$ChoiceNumber]
                }
            }
            else {
                [array]$FinalPackagesSelectedForUninstall = $PSGetInstalledPackageObjects
            }
        }
        if ($PSGetInstalledPackageObjects.Count -eq 1 -or
        $($PSGetInstalledPackageObjects.Count -gt 1 -and $UninstallAllSimilarlyNamedPackages)) {
            [array]$FinalPackagesSelectedForUninstall = $PSGetInstalledPackageObjects
        }
            
        # Make sure that we uninstall Packages where 'ProviderName' is 'Programs' LAST
        foreach ($Package in $FinalPackagesSelectedForUninstall) {
            if ($Package.ProviderName -ne "Programs") {
                Write-Host "Uninstalling $($Package.Name)..."
                $UninstallResult = $Package | Uninstall-Package -Force -Confirm:$False -ErrorAction SilentlyContinue
            }
        }
        foreach ($Package in $FinalPackagesSelectedForUninstall) {
            if ($Package.ProviderName -eq "Programs") {
                Write-Host "Uninstalling $($Package.Name)..."
                $UninstallResult = $Package | Uninstall-Package -Force -Confirm:$False -ErrorAction SilentlyContinue
            }
        }
    }

    try {
        $PackageManagerInstallObjects = Get-AllPackageInfo -ProgramName $ProgramName -ErrorAction SilentlyContinue
        [array]$ChocolateyInstalledProgramObjects = $PackageManagerInstallObjects.ChocolateyInstalledProgramObjects
        [array]$PSGetInstalledPackageObjects = $PackageManagerInstallObjects.PSGetInstalledPackageObjects
        [array]$RegistryProperties = $PackageManagerInstallObjects.RegistryProperties
        [array]$AppxInstalledPackageObjects = $PackageManagerInstallObjects.AppxAvailablePackages
    }
    catch {
        Write-Error $_
        $global:FunctionResult = "1"
        return
    }

    # If we found an install that was handled by Chocolatey, then uninstall via Chocolatey
    if ($ChocolateyInstalledProgramObjects.Count -gt 0) {
        if ($ChocolateyInstalledProgramObjects.Count -gt 1 -and !$UninstallAllSimilarlyNamedPackages) {
            Write-Warning "Multiple packages matching the name '$ProgramName' have been found via searching the chocolatey cmdline."

            for ($i=0; $i -lt $ChocolateyInstalledProgramObjects.Count; $i++) {
                Write-Host "$i) $($ChocolateyInstalledProgramObjects[$i].ProgramName)"
            }
            Write-Host "$($ChocolateyInstalledProgramObjects.Count)) All of the Above"

            [int[]]$ValidChoiceNumbers = 0..$($ChocolateyInstalledProgramObjects.Count)
            $UninstallChoice = Read-Host -Prompt "Please enter one or more numbers (separated by commas) that correspond to the program(s) you would like to uninstall."
            if ($UninstallChoice -match ',') {
                [array]$UninstallChoiceArray = $($UninstallChoice -split ',').Trim()
            }
            else {
                [array]$UninstallChoiceArray = $UninstallChoice
            }

            [System.Collections.ArrayList]$InvalidChoices = @()
            foreach ($ChoiceNumber in $UninstallChoiceArray) {
                if ($ValidChoiceNumbers -notcontains $ChoiceNumber) {
                    $null = $InvalidChoices.Add($ChoiceNumber)
                }
            }

            while ($InvalidChoices.Count -ne 0) {
                Write-Warning "The following selections are NOT valid Choice Numbers: $($InvalidChoices -join ', ')"

                $UninstallChoice = Read-Host -Prompt "Please enter one or more numbers (separated by commas) that correspond to the program(s) you would like to uninstall."
                if ($UninstallChoice -match ',') {
                    [array]$UninstallChoiceArray = $($UninstallChoice -split ',').Trim()
                }
                else {
                    [array]$UninstallChoiceArray = $UninstallChoice
                }

                [System.Collections.ArrayList]$InvalidChoices = @()
                foreach ($ChoiceNumber in $UninstallChoiceArray) {
                    if ($ValidChoiceNumbers -notcontains $ChoiceNumber) {
                        $null = $InvalidChoices.Add($ChoiceNumber)
                    }
                }
            }

            # Make sure that $UninstallChoiceArray is an integer array sorted 0..N
            try {
                [int[]]$UninstallChoiceArray = $UninstallChoiceArray | Sort-Object
            }
            catch {
                Write-Error $_
                Write-Error "`$UninstallChoiceArray cannot be converted to an array of integers! Halting!"
                $global:FunctionResult = "1"
                return
            }

            if ($UninstallChoiceArray -notcontains $ChocolateyInstalledProgramObjects.Count) {
                [array]$FinalPackagesSelectedForUninstall = foreach ($ChoiceNumber in $UninstallChoiceArray) {
                    $ChocolateyInstalledProgramObjects[$ChoiceNumber]
                }
            }
            else {
                [array]$FinalPackagesSelectedForUninstall = $ChocolateyInstalledProgramObjects
            }
        }
        if ($ChocolateyInstalledProgramObjects.Count -eq 1 -or
        $($ChocolateyInstalledProgramObjects.Count -gt 1 -and $UninstallAllSimilarlyNamedPackages)) {
            [array]$FinalPackagesSelectedForUninstall = $ChocolateyInstalledProgramObjects
        }
            
        # Do the uninstall
        [System.Collections.ArrayList]$ChocoUninstallFailures = @()
        [System.Collections.ArrayList]$ChocoUninstallSuccesses = @()
        foreach ($Package in $FinalPackagesSelectedForUninstall) {
            Write-Host "Uninstalling $($Package.ProgramName)..."
            #choco uninstall $Package.ProgramName -y --force # optionally add the following parameters: -n --remove-dependencies

            #Write-Host "Running $($(Get-Command choco).Source) uninstall $($ProgramObj.ProgramName) -y"
            $ProcessInfo = New-Object System.Diagnostics.ProcessStartInfo
            #$ProcessInfo.WorkingDirectory = $BinaryPath | Split-Path -Parent
            $ProcessInfo.FileName = $(Get-Command choco).Source
            $ProcessInfo.RedirectStandardError = $true
            $ProcessInfo.RedirectStandardOutput = $true
            $ProcessInfo.UseShellExecute = $false
            $ProcessInfo.Arguments = "uninstall $($Package.ProgramName) -y --force" # optionally -n --remove-dependencies
            $Process = New-Object System.Diagnostics.Process
            $Process.StartInfo = $ProcessInfo
            $Process.Start() | Out-Null
            # Below $FinishedInAlottedTime returns boolean true/false
            # Give it 120 seconds to finish the uninstall
            $FinishedInAlottedTime = $Process.WaitForExit(120000)
            if (!$FinishedInAlottedTime) {
                $Process.Kill()
            }
            $stdout = $Process.StandardOutput.ReadToEnd()
            $stderr = $Process.StandardError.ReadToEnd()
            $AllOutput = $stdout + $stderr

            if ($AllOutput -match "failed") {
                $null = $ChocoUninstallFailures.Add($ProgramObj)
            }
            else {
                $null = $ChocoUninstallSuccesses.Add($ProgramObj)
            }
        }
    }

    # Check to see if the program is still installed
    try {
        $PackageManagerInstallObjects = Get-AllPackageInfo -ProgramName $ProgramName -ErrorAction SilentlyContinue
        [array]$ChocolateyInstalledProgramObjects = $PackageManagerInstallObjects.ChocolateyInstalledProgramObjects
        [array]$PSGetInstalledPackageObjects = $PackageManagerInstallObjects.PSGetInstalledPackageObjects
        [array]$RegistryProperties = $PackageManagerInstallObjects.RegistryProperties
        [array]$AppxInstalledPackageObjects = $PackageManagerInstallObjects.AppxAvailablePackages
    }
    catch {
        Write-Error $_
        $global:FunctionResult = "1"
        return
    }

    # If we still have lingering packages, we need to try uninstall via what the Registry says the uninstall command is...
    if ($RegistryProperties.Count -gt 0) {
        if ($RegistryProperties.Count -gt 1 -and !$UninstallAllSimilarlyNamedPackages) {
            Write-Warning "Multiple packages matching the name '$ProgramName' have been found in the registry."

            for ($i=0; $i -lt $RegistryProperties.Count; $i++) {
                Write-Host "$i) $($RegistryProperties[$i].ProductName)"
            }
            Write-Host "$($RegistryProperties.Count)) All of the Above"

            [int[]]$ValidChoiceNumbers = 0..$($RegistryProperties.Count)
            $UninstallChoice = Read-Host -Prompt "Please enter one or more numbers (separated by commas) that correspond to the program(s) you would like to uninstall."
            if ($UninstallChoice -match ',') {
                [array]$UninstallChoiceArray = $($UninstallChoice -split ',').Trim()
            }
            else {
                [array]$UninstallChoiceArray = $UninstallChoice
            }

            [System.Collections.ArrayList]$InvalidChoices = @()
            foreach ($ChoiceNumber in $UninstallChoiceArray) {
                if ($ValidChoiceNumbers -notcontains $ChoiceNumber) {
                    $null = $InvalidChoices.Add($ChoiceNumber)
                }
            }

            while ($InvalidChoices.Count -ne 0) {
                Write-Warning "The following selections are NOT valid Choice Numbers: $($InvalidChoices -join ', ')"

                $UninstallChoice = Read-Host -Prompt "Please enter one or more numbers (separated by commas) that correspond to the program(s) you would like to uninstall."
                if ($UninstallChoice -match ',') {
                    [array]$UninstallChoiceArray = $($UninstallChoice -split ',').Trim()
                }
                else {
                    [array]$UninstallChoiceArray = $UninstallChoice
                }

                [System.Collections.ArrayList]$InvalidChoices = @()
                foreach ($ChoiceNumber in $UninstallChoiceArray) {
                    if ($ValidChoiceNumbers -notcontains $ChoiceNumber) {
                        $null = $InvalidChoices.Add($ChoiceNumber)
                    }
                }
            }

            # Make sure that $UninstallChoiceArray is an integer array sorted 0..N
            try {
                [int[]]$UninstallChoiceArray = $UninstallChoiceArray | Sort-Object
            }
            catch {
                Write-Error $_
                Write-Error "`$UninstallChoiceArray cannot be converted to an array of integers! Halting!"
                $global:FunctionResult = "1"
                return
            }

            if ($UninstallChoiceArray -notcontains $RegistryProperties.Count) {
                [array]$FinalPackagesSelectedForUninstall = foreach ($ChoiceNumber in $UninstallChoiceArray) {
                    $RegistryProperties[$ChoiceNumber]
                }
            }
            else {
                [array]$FinalPackagesSelectedForUninstall = $RegistryProperties
            }
        }
        if ($RegistryProperties.Count -eq 1 -or $($RegistryProperties.Count -gt 1 -and $UninstallAllSimilarlyNamedPackages)) {
            [array]$FinalPackagesSelectedForUninstall = $RegistryProperties
        }

        foreach ($Package in $FinalPackagesSelectedForUninstall) {
            if ($Package.QuietUninstallString -ne $null) {
                Invoke-Expression "& $($Package.QuietUninstallString)"
            }
        }
    }

    try {
        $PackageManagerInstallObjects = Get-AllPackageInfo -ProgramName $ProgramName -ErrorAction SilentlyContinue
        [array]$ChocolateyInstalledProgramObjects = $PackageManagerInstallObjects.ChocolateyInstalledProgramObjects
        [array]$PSGetInstalledPackageObjects = $PackageManagerInstallObjects.PSGetInstalledPackageObjects
        [array]$RegistryProperties = $PackageManagerInstallObjects.RegistryProperties
        [array]$AppxInstalledPackageObjects = $PackageManagerInstallObjects.AppxAvailablePackages
    }
    catch {
        Write-Error $_
        $global:FunctionResult = "1"
        return
    }

    [System.Collections.ArrayList]$DirectoriesThatMightNeedToBeRemoved = @()

    # If we STILL have lingering packages, tell the user what they *might* need to delete in order to finish the uninstall
    if ($RegistryProperties.Count -gt 0) {    
        foreach ($Program in $RegistryProperties) {
            if (Test-Path $Program.PSPath) {
                $null = $DirectoriesThatMightNeedToBeRemoved.Add($Program.PSPath)
                #Remove-Item -Path $Program.PSPath -Recurse -Force
            }
        }
    }

    # We MIGHT be able to get the directory where the Program's binaries are by using Get-Command.
    $ProgramExePath = $(Get-Command $ProgramName -ErrorAction SilentlyContinue).Source
    if ($ProgramExePath) {
        $ProgramParentDirPath = $ProgramExePath | Split-Path -Parent
    }
    if ($ProgramParentDirPath) {
        if (Test-Path $ProgramParentDirPath) {
            $null = $DirectoriesThatMightNeedToBeRemoved.Add($ProgramParentDirPath)
            #Remove-Item $ProgramParentDirPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    if ($ChocolateyInstalledProgramObjects.Count -gt 0 -or $PSGetInstalledPackageObjects.Count -gt 0 -or $RegistryProperties.Count -gt 0 -or $DirectoriesThatMightNeedToBeRemoved.Count -gt 0) {
        Write-Warning "The program '$ProgramName' did NOT cleanly uninstall. Please review output of the Uninstall-Program function for details about lingering references."
    }
    else {
        Write-Host "The program '$ProgramName' was uninstalled successfully!" -ForegroundColor Green
    }

    [pscustomobject]@{
        DirectoriesThatMightNeedToBeRemoved = [array]$DirectoriesThatMightNeedToBeRemoved
        ChocolateyInstalledProgramObjects   = [array]$ChocolateyInstalledProgramObjects
        PSGetInstalledPackageObjects        = [array]$PSGetInstalledPackageObjects
        RegistryProperties                  = [array]$RegistryProperties
    }

    #endregion >> Main Body
}


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


<#
    .SYNOPSIS
        Install and/or Update the PackageManagement PowerShell Module and/or the PowerShellGet PowerShell Module.

        IMPORTANT: This script can be used on systems with PowerShell Version 3 and higher

    .DESCRIPTION
        PowerShell versions 3 and 4 do NOT have the PackageManagement and PowerShellGet Modules installed by default.
        If you are running PowerShell 3 or 4 and these modules are NOT installed, it will download PackageMangement_x64.msi
        from Microsoft and install it (thereby installing the Modules) and upgrade the Modules the latest version available
        in the PSGallery PackageProvider Source repo (NOTE: The PackageManagement module is not able to be upgraded beyond
        version 1.0.0.1 on PowerShell 3 or 4, unless you upgrade PowerShell itself to version 5 or higher).

        PowerShell version 5 and higher DOES come with PackageManagement and PowerShellGet Modules (both version
        1.0.0.1) by default. This script will install the latest versions of these Modules ALONGSIDE
        (i.e. SIDE-BY-SIDE MODE) the older versions...because that's apparently how Microsoft wants to
        handle this for the time being.

        At the conclusion of this script, the PowerShell Sessionw will have the latest versions of the PackageManagement and 
        PowerShellGet Modules loaded via Import-Module. (Verify with Get-Module).

    .NOTES
        ##### Regarding PowerShell Versions Lower than 5 #####

        Installation of the PackageManagement_x64.msi is necessary. Installing this .msi gives us version 1.0.0.1 of the 
        PackageManagement Module and version 1.0.0.1 of PowerShellGet Module (as well as the PowerShellGet PackageProvider 
        and the PowerShellGet PackageProvider Source called PSGallery).

        However, these are NOT the latest versions of these Modules. You can update the PowerShellGet Module from 1.0.0.1 to
        the latest version by using Install-Module -Force. Unfortunately, it is not possible to update the PackageManagement
        Module itself using this method, because it will complain about it being in use (which it is, since the Install-Module
        cmdlet belongs to the PackageManagement Module).

        It is important to note that updating PowerShellGet using Install-Module -Force in PowerShell versions lower than 5
        actually REMOVES 1.0.0.1 and REPLACES it with the latest version. (In PowerShell version 5 and higher, it installs
        the new version of the Module ALONGSIDE the old version.)

        There is currently no way to update the PackageManagement Module to a version newer than 1.0.0.1 without actually updating
        PowerShell itself to version 5 or higher.


        ##### Regarding PowerShell Versions 5 And Higher #####

        The PackageManagement Module version 1.0.0.1 and PowerShellGet Module version 1.0.0.1 are already installed.

        It is possible to update both Modules using Install-Module -Force, HOWEVER, the newer versions will be installed
        ALONGSIDE (aka SIDE-BY-SIDE mode) the older versions. In future PowerShell Sessions, you need to specify which version
        you want to use when you import the module(s) using Import-Module -RequiredVersion

    .EXAMPLE
        Update-PackageManagement -AddChocolateyPackageProvider

#>

function Update-PackageManagement {
    [CmdletBinding()]
    Param( 
        [Parameter(Mandatory=$False)]
        [switch]$AddChocolateyPackageProvider,

        [Parameter(Mandatory=$False)]
        [switch]$InstallNuGetCmdLine,

        [Parameter(Mandatory=$False)]
        [switch]$LoadUpdatedModulesInSameSession
    )

    ##### BEGIN Variable/Parameter Transforms and PreRun Prep #####

    # We're going to need Elevated privileges for some commands below, so might as well try to set this up now.
    if (!$(GetElevation)) {
        Write-Error "The Update-PackageManagement function must be run with elevated privileges. Halting!"
        $global:FunctionResult = "1"
        return
    }

    if (!$([Environment]::Is64BitProcess)) {
        Write-Error "You are currently running the 32-bit version of PowerShell. Please run the 64-bit version found under C:\Windows\SysWOW64\WindowsPowerShell\v1.0 and try again. Halting!"
        $global:FunctionResult = "1"
        return
    }

    if ($PSVersionTable.PSEdition -eq "Core" -and $PSVersionTable.Platform -ne "Win32NT" -and $AddChocolateyPackageProvider) {
        Write-Error "The Chocolatey Repo should only be added on a Windows OS! Halting!"
        $global:FunctionResult = "1"
        return
    }

    if ($InstallNuGetCmdLine -and !$AddChocolateyPackageProvider) {
        if ($PSVersionTable.PSEdition -eq "Desktop" -or $PSVersionTable.PSVersion.Major -le 5) {
            if ($(Get-PackageProvider).Name -notcontains "Chocolatey") {
                $WarningMessage = "NuGet Command Line Tool cannot be installed without using Chocolatey. Would you like to use the Chocolatey Package Provider (NOTE: This is NOT an installation of the chocolatey command line)?"
                $WarningResponse = PauseForWarning -PauseTimeInSeconds 15 -Message $WarningMessage
                if ($WarningResponse) {
                    $AddChocolateyPackageProvider = $true
                }
            }
            else {
                $AddChocolateyPackageProvider = $true
            }
        }
        elseif ($PSVersionTable.PSEdition -eq "Core" -and $PSVersionTable.Platform -eq "Win32NT") {
            if (!$(Get-Command choco -ErrorAction SilentlyContinue)) {
                $WarningMessage = "NuGet Command Line Tool cannot be installed without using Chocolatey. Would you like to install Chocolatey Command Line Tools in order to install NuGet Command Line Tools?"
                $WarningResponse = PauseForWarning -PauseTimeInSeconds 15 -Message $WarningMessage
                if ($WarningResponse) {
                    $AddChocolateyPackageProvider = $true
                }
            }
            else {
                $AddChocolateyPackageProvider = $true
            }
        }
        elseif ($PSVersionTable.PSEdition -eq "Core" -and $PSVersionTable.Platform -eq "Unix") {
            $WarningMessage = "The NuGet Command Line Tools binary nuget.exe can be downloaded, but will not be able to be run without Mono. Do you want to download the latest stable nuget.exe?"
            $WarningResponse = PauseForWarning -PauseTimeInSeconds 15 -Message $WarningMessage
            if ($WarningResponse) {
                Write-Host "Downloading latest stable nuget.exe..."
                $OutFilePath = GetNativePath -PathAsStringArray @($HOME, "Downloads", "nuget.exe")
                #Invoke-WebRequest -Uri "https://dist.nuget.org/win-x86-commandline/latest/nuget.exe" -OutFile $OutFilePath
                [Net.ServicePointManager]::SecurityProtocol = "tls12, tls11, tls"
                [System.Net.WebClient]::new().Downloadfile("https://dist.nuget.org/win-x86-commandline/latest/nuget.exe", $OutFilePath)
            }
            $AddChocolateyPackageProvider = $false
        }
    }

    if ($PSVersionTable.PSEdition -eq "Desktop" -or $PSVersionTable.PSVersion.Major -le 5) {
        # Check to see if we're behind a proxy
        if ([System.Net.WebProxy]::GetDefaultProxy().Address -ne $null) {
            $ProxyAddress = [System.Net.WebProxy]::GetDefaultProxy().Address
            [system.net.webrequest]::defaultwebproxy = New-Object system.net.webproxy($ProxyAddress)
            [system.net.webrequest]::defaultwebproxy.credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials
            [system.net.webrequest]::defaultwebproxy.BypassProxyOnLocal = $true
        }
    }
    # TODO: Figure out how to identify default proxy on PowerShell Core...

    ##### END Variable/Parameter Transforms and PreRun Prep #####


    if ($PSVersionTable.PSVersion.Major -lt 5) {
        if ($(Get-Module -ListAvailable).Name -notcontains "PackageManagement") {
            Write-Host "Downloading PackageManagement .msi installer..."
            $OutFilePath = GetNativePath -PathAsStringArray @($HOME, "Downloads", "PackageManagement_x64.msi")
            #Invoke-WebRequest -Uri "https://download.microsoft.com/download/C/4/1/C41378D4-7F41-4BBE-9D0D-0E4F98585C61/PackageManagement_x64.msi" -OutFile $OutFilePath
            [Net.ServicePointManager]::SecurityProtocol = "tls12, tls11, tls"
            [System.Net.WebClient]::new().Downloadfile("https://download.microsoft.com/download/C/4/1/C41378D4-7F41-4BBE-9D0D-0E4F98585C61/PackageManagement_x64.msi", $OutFilePath)
            
            $DateStamp = Get-Date -Format yyyyMMddTHHmmss
            $MSIFullPath = $OutFilePath
            $MSIParentDir = $MSIFullPath | Split-Path -Parent
            $MSIFileName = $MSIFullPath | Split-Path -Leaf
            $MSIFileNameOnly = $MSIFileName -replace "\.msi",""
            $logFile = GetNativePath -PathAsStringArray @($MSIParentDir, "$MSIFileNameOnly$DateStamp.log")
            $MSIArguments = @(
                "/i"
                $MSIFullPath
                "/qn"
                "/norestart"
                "/L*v"
                $logFile
            )
            Start-Process "msiexec.exe" -ArgumentList $MSIArguments -Wait -NoNewWindow
        }
        while ($($(Get-Module -ListAvailable).Name -notcontains "PackageManagement") -and $($(Get-Module -ListAvailable).Name -notcontains "PowerShellGet")) {
            Write-Host "Waiting for PackageManagement and PowerShellGet Modules to become available"
            Start-Sleep -Seconds 1
        }
        Write-Host "PackageManagement and PowerShellGet Modules are ready. Continuing..."
    }

    # We need to load whatever versions of PackageManagement/PowerShellGet are available on the Local Host in order
    # to use the Find-Module cmdlet to find out what the latest versions of each Module are...

    # ...but because there are sometimes issues with version compatibility between PackageManagement/PowerShellGet,
    # after loading the latest PackageManagement Module we need to try/catch available versions of PowerShellGet until
    # one of them actually loads
    
    # Set LatestLocallyAvailable variables...
    $PackageManagementLatestLocallyAvailableVersionItem = $(Get-Module -ListAvailable -All | Where-Object {$_.Name -eq "PackageManagement"} | Sort-Object -Property Version)[-1]
    $PowerShellGetLatestLocallyAvailableVersionItem = $(Get-Module -ListAvailable -All | Where-Object {$_.Name -eq "PowerShellGet"} | Sort-Object -Property Version)[-1]
    $PackageManagementLatestLocallyAvailableVersion = $PackageManagementLatestLocallyAvailableVersionItem.Version
    $PowerShellGetLatestLocallyAvailableVersion = $PowerShellGetLatestLocallyAvailableVersionItem.Version
    $PSGetLocallyAvailableVersions = $(Get-Module -ListAvailable -All | Where-Object {$_.Name -eq "PowerShellGet"}).Version | Sort-Object -Property Version | Get-Unique
    $PSGetLocallyAvailableVersions = $PSGetLocallyAvailableVersions | Sort-Object -Descending
    

    if ($(Get-Module).Name -notcontains "PackageManagement") {
        if ($PSVersionTable.PSVersion.Major -ge 5) {
            Import-Module "PackageManagement" -RequiredVersion $PackageManagementLatestLocallyAvailableVersion
        }
        else {
            Import-Module "PackageManagement"
        }
    }
    if ($(Get-Module).Name -notcontains "PowerShellGet") {
        foreach ($version in $PSGetLocallyAvailableVersions) {
            try {
                $ImportedPSGetModule = Import-Module "PowerShellGet" -RequiredVersion $version -PassThru -ErrorAction SilentlyContinue
                if (!$ImportedPSGetModule) {throw}

                break
            }
            catch {
                continue
            }
        }
    }

    if ($(Get-Module -Name PackageManagement).ExportedCommands.Count -eq 0 -or
        $(Get-Module -Name PowerShellGet).ExportedCommands.Count -eq 0
    ) {
        Write-Warning "Either PowerShellGet or PackagementManagement Modules were not able to be loaded Imported successfully due to an update initiated within the current session. Please close this PowerShell Session, open a new one, and run this function again."

        $Result = [pscustomobject][ordered]@{
            PackageManagementUpdated  = $false
            PowerShellGetUpdated      = $false
            NewPSSessionRequired      = $true
        }

        $Result
        return
    }

    # Determine if the NuGet Package Provider is available. If not, install it, because it needs it for some reason
    # that is currently not clear to me. Point is, if it's not installed it will prompt you to install it, so just
    # do it beforehand.
    if ($(Get-PackageProvider).Name -notcontains "NuGet") {
        Install-PackageProvider "NuGet" -Scope CurrentUser -Force
        Register-PackageSource -Name 'nuget.org' -Location 'https://api.nuget.org/v3/index.json' -ProviderName NuGet -Trusted -Force -ForceBootstrap
    }

    if ($AddChocolateyPackageProvider) {
        if ($PSVersionTable.PSEdition -eq "Desktop" -or $PSVersionTable.PSVersion.Major -le 5) {
            # Install the Chocolatey Package Provider to be used with PowerShellGet
            if ($(Get-PackageProvider).Name -notcontains "Chocolatey") {
                Install-PackageProvider "Chocolatey" -Scope CurrentUser -Force
                # The above Install-PackageProvider "Chocolatey" -Force DOES register a PackageSource Repository, so we need to trust it:
                Set-PackageSource -Name Chocolatey -Trusted

                # Make sure packages installed via Chocolatey PackageProvider are part of $env:Path
                [System.Collections.ArrayList]$ChocolateyPathsPrep = @()
                [System.Collections.ArrayList]$ChocolateyPathsFinal = @()
                $env:ChocolateyPSProviderPath = "C:\Chocolatey"

                if (Test-Path $env:ChocolateyPSProviderPath) {
                    if (Test-Path "$env:ChocolateyPSProviderPath\lib") {
                        $OtherChocolateyPathsToAdd = $(Get-ChildItem "$env:ChocolateyPSProviderPath\lib" -Directory | foreach {
                            Get-ChildItem $_.FullName -Recurse -File
                        } | foreach {
                            if ($_.Extension -eq ".exe") {
                                $_.Directory.FullName
                            }
                        }) | foreach {
                            $null = $ChocolateyPathsPrep.Add($_)
                        }
                    }
                    if (Test-Path "$env:ChocolateyPSProviderPath\bin") {
                        $OtherChocolateyPathsToAdd = $(Get-ChildItem "$env:ChocolateyPSProviderPath\bin" -Directory | foreach {
                            Get-ChildItem $_.FullName -Recurse -File
                        } | foreach {
                            if ($_.Extension -eq ".exe") {
                                $_.Directory.FullName
                            }
                        }) | foreach {
                            $null = $ChocolateyPathsPrep.Add($_)
                        }
                    }
                }
                
                if ($ChocolateyPathsPrep) {
                    foreach ($ChocoPath in $ChocolateyPathsPrep) {
                        if ($(Test-Path $ChocoPath) -and $OriginalEnvPathArray -notcontains $ChocoPath) {
                            $null = $ChocolateyPathsFinal.Add($ChocoPath)
                        }
                    }
                }
            
                try {
                    $ChocolateyPathsFinal = $ChocolateyPathsFinal | Sort-Object | Get-Unique
                }
                catch {
                    [System.Collections.ArrayList]$ChocolateyPathsFinal = @($ChocolateyPathsFinal)
                }
                if ($ChocolateyPathsFinal.Count -ne 0) {
                    $ChocolateyPathsAsString = $ChocolateyPathsFinal -join ";"
                }

                foreach ($ChocPath in $ChocolateyPathsFinal) {
                    if ($($env:Path -split ";") -notcontains $ChocPath) {
                        if ($env:Path[-1] -eq ";") {
                            $env:Path = "$env:Path$ChocPath"
                        }
                        else {
                            $env:Path = "$env:Path;$ChocPath"
                        }
                    }
                }

                if ($InstallNuGetCmdLine) {
                    # Next, install the NuGet CLI using the Chocolatey Repo
                    try {
                        Write-Host "Trying to find Chocolatey Package Nuget.CommandLine..."
                        while (!$(Find-Package Nuget.CommandLine)) {
                            Write-Host "Trying to find Chocolatey Package Nuget.CommandLine..."
                            Start-Sleep -Seconds 2
                        }
                        
                        Get-Package NuGet.CommandLine -ErrorAction SilentlyContinue
                        if (!$?) {
                            throw
                        }
                    } 
                    catch {
                        Install-Package Nuget.CommandLine -Source chocolatey -Force
                    }
                    
                    # Ensure there's a symlink from C:\Chocolatey\bin to the real NuGet.exe under C:\Chocolatey\lib
                    $NuGetSymlinkTest = Get-ChildItem "C:\Chocolatey\bin" | Where-Object {$_.Name -eq "NuGet.exe" -and $_.LinkType -eq "SymbolicLink"}
                    $RealNuGetPath = $(Resolve-Path "C:\Chocolatey\lib\*\*\NuGet.exe").Path
                    $TestRealNuGetPath = Test-Path $RealNuGetPath
                    if (!$NuGetSymlinkTest -and $TestRealNuGetPath) {
                        New-Item -Path "C:\Chocolatey\bin\NuGet.exe" -ItemType SymbolicLink -Value $RealNuGetPath
                    }
                }
            }
        }
        if ($PSVersionTable.PSEdition -eq "Core" -and $PSVersionTable.Platform -eq "Win32NT") {
            # Install the Chocolatey Command line
            if (!$(Get-Command choco -ErrorAction SilentlyContinue)) {
                # Suppressing all errors for Chocolatey cmdline install. They will only be a problem if
                # there is a Web Proxy between you and the Internet
                $env:chocolateyUseWindowsCompression = 'true'
                $null = Invoke-Expression $([System.Net.WebClient]::new()).DownloadString("https://chocolatey.org/install.ps1") -ErrorVariable ChocolateyInstallProblems 2>&1 6>&1
                $DateStamp = Get-Date -Format yyyyMMddTHHmmss
                $ChocolateyInstallLogFile = GetNativePath -PathAsStringArray @($(Get-Location).Path, "ChocolateyInstallLog_$DateStamp.txt")
                $ChocolateyInstallProblems | Out-File $ChocolateyInstallLogFile
            }

            if ($InstallNuGetCmdLine) {
                if (!$(Get-Command choco -ErrorAction SilentlyContinue)) {
                    Write-Error "Unable to find chocolatey.exe, however, it should be installed. Please check your System PATH and `$env:Path and try again. Halting!"
                    $global:FunctionResult = "1"
                    return
                }
                else {
                    # 'choco update' aka 'cup' will update if already installed or install if not installed
                    $ProcessInfo = New-Object System.Diagnostics.ProcessStartInfo
                    $ProcessInfo.WorkingDirectory = $NuGetPackagesPath
                    $ProcessInfo.FileName = "cup"
                    $ProcessInfo.RedirectStandardError = $true
                    $ProcessInfo.RedirectStandardOutput = $true
                    $ProcessInfo.UseShellExecute = $false
                    $ProcessInfo.Arguments = "nuget.commandline -y"
                    $Process = New-Object System.Diagnostics.Process
                    $Process.StartInfo = $ProcessInfo
                    $Process.Start() | Out-Null
                    $stdout = $($Process.StandardOutput.ReadToEnd()).Trim()
                    $stderr = $($Process.StandardError.ReadToEnd()).Trim()
                    $AllOutput = $stdout + $stderr
                    $AllOutput = $AllOutput -split "`n"
                }
                # NOTE: The chocolatey install should take care of setting $env:Path and System PATH so that
                # choco binaries and packages installed via chocolatey can be found here:
                # C:\ProgramData\chocolatey\bin
            }
        }
    }
    # Next, set the PSGallery PowerShellGet PackageProvider Source to Trusted
    if ($(Get-PackageSource | Where-Object {$_.Name -eq "PSGallery"}).IsTrusted -eq $False) {
        Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
    }

    # Next, update PackageManagement and PowerShellGet where possible
    [version]$MinimumVer = "1.0.0.1"
    try {
        $PackageManagementLatestVersion = $(Find-Module PackageManagement).Version
    }
    catch {
        $PackageManagementLatestVersion = $PackageManagementLatestLocallyAvailableVersion
    }
    try {
        $PowerShellGetLatestVersion = $(Find-Module PowerShellGet).Version
    }
    catch {
        $PowerShellGetLatestVersion = $PowerShellGetLatestLocallyAvailableVersion
    }
    Write-Verbose "PackageManagement Latest Version is: $PackageManagementLatestVersion"
    Write-Verbose "PowerShellGetLatestVersion Latest Version is: $PowerShellGetLatestVersion"

    if ($PackageManagementLatestVersion -gt $PackageManagementLatestLocallyAvailableVersion -and $PackageManagementLatestVersion -gt $MinimumVer) {
        if ($PSVersionTable.PSVersion.Major -lt 5) {
            Write-Host "`nUnable to update the PackageManagement Module beyond $($MinimumVer.ToString()) on PowerShell versions lower than 5."
        }
        if ($PSVersionTable.PSVersion.Major -ge 5) {
            #Install-Module -Name "PackageManagement" -Scope CurrentUser -Repository PSGallery -RequiredVersion $PowerShellGetLatestVersion -Force -WarningAction "SilentlyContinue"
            #Install-Module -Name "PackageManagement" -Scope CurrentUser -Repository PSGallery -RequiredVersion $PackageManagementLatestVersion -Force
            Write-Host "Installing latest version of PackageManagement..."
            Install-Module -Name "PackageManagement" -Force -WarningAction SilentlyContinue
            $PackageManagementUpdated = $True
        }
    }
    if ($PowerShellGetLatestVersion -gt $PowerShellGetLatestLocallyAvailableVersion -and $PowerShellGetLatestVersion -gt $MinimumVer) {
        # Unless the force parameter is used, Install-Module will halt with a warning saying the 1.0.0.1 is already installed
        # and it will not update it.
        Write-Host "Installing latest version of PowerShellGet..."
        #Install-Module -Name "PowerShellGet" -Scope CurrentUser -Repository PSGallery -RequiredVersion $PowerShellGetLatestVersion -Force -WarningAction "SilentlyContinue"
        #Install-Module -Name "PowerShellGet" -RequiredVersion $PowerShellGetLatestVersion -Force
        Install-Module -Name "PowerShellGet" -Force -WarningAction SilentlyContinue
        $PowerShellGetUpdated = $True
    }

    # Reset the LatestLocallyAvailable variables, and then load them into the current session
    $PackageManagementLatestLocallyAvailableVersionItem = $(Get-Module -ListAvailable -All | Where-Object {$_.Name -eq "PackageManagement"} | Sort-Object -Property Version)[-1]
    $PowerShellGetLatestLocallyAvailableVersionItem = $(Get-Module -ListAvailable -All | Where-Object {$_.Name -eq "PowerShellGet"} | Sort-Object -Property Version)[-1]
    $PackageManagementLatestLocallyAvailableVersion = $PackageManagementLatestLocallyAvailableVersionItem.Version
    $PowerShellGetLatestLocallyAvailableVersion = $PowerShellGetLatestLocallyAvailableVersionItem.Version
    Write-Verbose "Latest locally available PackageManagement version is $PackageManagementLatestLocallyAvailableVersion"
    Write-Verbose "Latest locally available PowerShellGet version is $PowerShellGetLatestLocallyAvailableVersion"

    $CurrentlyLoadedPackageManagementVersion = $(Get-Module | Where-Object {$_.Name -eq 'PackageManagement'}).Version
    $CurrentlyLoadedPowerShellGetVersion = $(Get-Module | Where-Object {$_.Name -eq 'PowerShellGet'}).Version
    Write-Verbose "Currently loaded PackageManagement version is $CurrentlyLoadedPackageManagementVersion"
    Write-Verbose "Currently loaded PowerShellGet version is $CurrentlyLoadedPowerShellGetVersion"

    if ($PackageManagementUpdated -eq $True -or $PowerShellGetUpdated -eq $True) {
        $NewPSSessionRequired = $True
        if ($LoadUpdatedModulesInSameSession) {
            if ($PowerShellGetUpdated -eq $True) {
                $PSGetWarningMsg = "Loading the latest installed version of PowerShellGet " +
                "(i.e. PowerShellGet $($PowerShellGetLatestLocallyAvailableVersion.ToString()) " +
                "in the current PowerShell session will break some PowerShellGet Cmdlets!"
                Write-Warning $PSGetWarningMsg
            }
            if ($PackageManagementUpdated -eq $True) {
                $PMWarningMsg = "Loading the latest installed version of PackageManagement " +
                "(i.e. PackageManagement $($PackageManagementLatestLocallyAvailableVersion.ToString()) " +
                "in the current PowerShell session will break some PackageManagement Cmdlets!"
                Write-Warning $PMWarningMsg
            }
        }
    }

    if ($LoadUpdatedModulesInSameSession) {
        if ($CurrentlyLoadedPackageManagementVersion -lt $PackageManagementLatestLocallyAvailableVersion) {
            # Need to remove PowerShellGet first since it depends on PackageManagement
            Write-Host "Removing Module PowerShellGet $CurrentlyLoadedPowerShellGetVersion ..."
            Remove-Module -Name "PowerShellGet"
            Write-Host "Removing Module PackageManagement $CurrentlyLoadedPackageManagementVersion ..."
            Remove-Module -Name "PackageManagement"
        
            if ($(Get-Host).Name -ne "Package Manager Host") {
                Write-Verbose "We are NOT in the Visual Studio Package Management Console. Continuing..."
                
                # Need to Import PackageManagement first since it's a dependency for PowerShellGet
                # Need to use -RequiredVersion parameter because older versions are still intalled side-by-side with new
                Write-Host "Importing PackageManagement Version $PackageManagementLatestLocallyAvailableVersion ..."
                $null = Import-Module "PackageManagement" -RequiredVersion $PackageManagementLatestLocallyAvailableVersion -ErrorVariable ImportPackManProblems 2>&1 6>&1
                Write-Host "Importing PowerShellGet Version $PowerShellGetLatestLocallyAvailableVersion ..."
                $null = Import-Module "PowerShellGet" -RequiredVersion $PowerShellGetLatestLocallyAvailableVersion -ErrorVariable ImportPSGetProblems 2>&1 6>&1
            }
            if ($(Get-Host).Name -eq "Package Manager Host") {
                Write-Verbose "We ARE in the Visual Studio Package Management Console. Continuing..."
        
                # Need to Import PackageManagement first since it's a dependency for PowerShellGet
                # Need to use -RequiredVersion parameter because older versions are still intalled side-by-side with new
                Write-Host "Importing PackageManagement Version $PackageManagementLatestLocallyAvailableVersion`nNOTE: Module Members will have with Prefix 'PackMan' - Example: Get-PackManPackage"
                $null = Import-Module "PackageManagement" -RequiredVersion $PackageManagementLatestLocallyAvailableVersion -Prefix PackMan -ErrorVariable ImportPackManProblems 2>&1 6>&1
                Write-Host "Importing PowerShellGet Version $PowerShellGetLatestLocallyAvailableVersion`nNOTE: Module Members will have with Prefix 'PSGet' - Example: Find-PSGetModule"
                $null = Import-Module "PowerShellGet" -RequiredVersion $PowerShellGetLatestLocallyAvailableVersion -Prefix PSGet -ErrorVariable ImportPSGetProblems 2>&1 6>&1
            }
        }
        
        # Reset CurrentlyLoaded Variables
        $CurrentlyLoadedPackageManagementVersion = $(Get-Module | Where-Object {$_.Name -eq 'PackageManagement'}).Version
        $CurrentlyLoadedPowerShellGetVersion = $(Get-Module | Where-Object {$_.Name -eq 'PowerShellGet'}).Version
        Write-Verbose "Currently loaded PackageManagement version is $CurrentlyLoadedPackageManagementVersion"
        Write-Verbose "Currently loaded PowerShellGet version is $CurrentlyLoadedPowerShellGetVersion"
        
        if ($CurrentlyLoadedPowerShellGetVersion -lt $PowerShellGetLatestLocallyAvailableVersion) {
            if (!$ImportPSGetProblems) {
                Write-Host "Removing Module PowerShellGet $CurrentlyLoadedPowerShellGetVersion ..."
            }
            Remove-Module -Name "PowerShellGet"
        
            if ($(Get-Host).Name -ne "Package Manager Host") {
                Write-Verbose "We are NOT in the Visual Studio Package Management Console. Continuing..."
                
                # Need to use -RequiredVersion parameter because older versions are still intalled side-by-side with new
                Write-Host "Importing PowerShellGet Version $PowerShellGetLatestLocallyAvailableVersion ..."
                Import-Module "PowerShellGet" -RequiredVersion $PowerShellGetLatestLocallyAvailableVersion
            }
            if ($(Get-Host).Name -eq "Package Manager Host") {
                Write-Host "We ARE in the Visual Studio Package Management Console. Continuing..."
        
                # Need to use -RequiredVersion parameter because older versions are still intalled side-by-side with new
                Write-Host "Importing PowerShellGet Version $PowerShellGetLatestLocallyAvailableVersion`nNOTE: Module Members will have with Prefix 'PSGet' - Example: Find-PSGetModule"
                Import-Module "PowerShellGet" -RequiredVersion $PowerShellGetLatestLocallyAvailableVersion -Prefix PSGet
            }
        }

        # Make sure all Repos Are Trusted
        if ($AddChocolateyPackageProvider -and $($PSVersionTable.PSEdition -eq "Desktop" -or $PSVersionTable.PSVersion.Major -le 5)) {
            $BaselineRepoNames = @("Chocolatey","nuget.org","PSGallery")
        }
        else {
            $BaselineRepoNames = @("nuget.org","PSGallery")
        }
        if ($(Get-Module -Name PackageManagement).ExportedCommands.Count -gt 0) {
            $RepoObjectsForTrustCheck = Get-PackageSource | Where-Object {$_.Name -match "$($BaselineRepoNames -join "|")"}
        
            foreach ($RepoObject in $RepoObjectsForTrustCheck) {
                if ($RepoObject.IsTrusted -ne $true) {
                    Set-PackageSource -Name $RepoObject.Name -Trusted
                }
            }
        }

        # Reset CurrentlyLoaded Variables
        $CurrentlyLoadedPackageManagementVersion = $(Get-Module | Where-Object {$_.Name -eq 'PackageManagement'}).Version
        $CurrentlyLoadedPowerShellGetVersion = $(Get-Module | Where-Object {$_.Name -eq 'PowerShellGet'}).Version
        Write-Verbose "The FINAL loaded PackageManagement version is $CurrentlyLoadedPackageManagementVersion"
        Write-Verbose "The FINAL loaded PowerShellGet version is $CurrentlyLoadedPowerShellGetVersion"

        #$ErrorsArrayReversed = $($Error.Count-1)..$($Error.Count-4) | foreach {$Error[$_]}
        #$CheckForError = try {$ErrorsArrayReversed[0].ToString()} catch {$null}
        if ($($ImportPackManProblems | Out-String) -match "Assembly with same name is already loaded" -or 
            $CurrentlyLoadedPackageManagementVersion -lt $PackageManagementLatestVersion -or
            $(Get-Module -Name PackageManagement).ExportedCommands.Count -eq 0
        ) {
            Write-Warning "The PackageManagement Module has been updated and requires and brand new PowerShell Session. Please close this session, start a new one, and run the function again."
            $NewPSSessionRequired = $true
        }
    }

    $Result = [pscustomobject][ordered]@{
        PackageManagementUpdated                     = if ($PackageManagementUpdated) {$true} else {$false}
        PowerShellGetUpdated                         = if ($PowerShellGetUpdated) {$true} else {$false}
        NewPSSessionRequired                         = if ($NewPSSessionRequired) {$true} else {$false}
        PackageManagementCurrentlyLoaded             = Get-Module -Name PackageManagement
        PowerShellGetCurrentlyLoaded                 = Get-Module -Name PowerShellGet
        PackageManagementLatesLocallyAvailable       = $PackageManagementLatestLocallyAvailableVersionItem
        PowerShellGetLatestLocallyAvailable          = $PowerShellGetLatestLocallyAvailableVersionItem
    }

    $Result
}


# Originally from: http://www.scconfigmgr.com/2014/08/22/how-to-get-msi-file-information-with-powershell/
function Update-SystemPathNow {
    [CmdletBinding()]
    param(
        [parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$PathToAdd
    )

    $RegKeyPath = 'Registry::HKEY_LOCAL_MACHINE\System\CurrentControlSet\Control\Session Manager\Environment'
    $CurrentSystemPath = $(Get-ItemProperty -Path $RegKeyPath -Name PATH).Path

    if ($CurrentSystemPath | Select-String -SimpleMatch $PathToAdd) {
        Write-Warning 'Folder already within $env:Path'
        return
    }

    $NewPath = $PathToAdd + ';' + $CurrentSystemPath

    # Update the Registry
    Set-ItemProperty -Path $RegKeyPath -Name PATH -Value $NewPath

    # Now the registry is updated, but current processes haven't taken the changes.
    # We will now force all open processes/windows to take the updated system PATH

    if (-not $("Win32.NativeMethods" -as [Type])) {
        # import sendmessagetimeout from win32
        $null = Add-Type -Namespace Win32 -Name NativeMethods -MemberDefinition @"
[DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
public static extern IntPtr SendMessageTimeout(
IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam,
uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);
"@
    }

    $HWND_BROADCAST = [IntPtr] 0xffff
    $WM_SETTINGCHANGE = 0x1a
    $result = [UIntPtr]::Zero

    # notify all windows of environment block change
    [Win32.Nativemethods]::SendMessageTimeout($HWND_BROADCAST, $WM_SETTINGCHANGE, [UIntPtr]::Zero, "Environment", 2, 5000, [ref] $result)
}


[System.Collections.ArrayList]$script:FunctionsForSBUse = @(
    ${Function:AddLastWriteTimeToRegKey}.Ast.Extent.Text
    ${Function:GetElevation}.Ast.Extent.Text
    ${Function:GetMSIFileInfo}.Ast.Extent.Text
    ${Function:GetNativePath}.Ast.Extent.Text
    ${Function:InvokePSCompatibility}.Ast.Extent.Text
    ${Function:MaualPSGalleryModuleInstall}.Ast.Extent.Text
    ${Function:PauseForWarning}.Ast.Extent.Text
    ${Function:UnzipFile}.Ast.Extent.Text
    ${Function:Get-AllPackageInfo}.Ast.Extent.Text
    ${Function:Get-ExePath}.Ast.Extent.Text
    ${Function:Get-InstalledProgramsFromRegistry}.Ast.Extent.Text
    ${Function:Install-ChocolateyCmdLine}.Ast.Extent.Text
    ${Function:Install-Program}.Ast.Extent.Text
    ${Function:New-Runspace}.Ast.Extent.Text
    ${Function:Uninstall-Program}.Ast.Extent.Text
    ${Function:Update-ChocolateyEnv}.Ast.Extent.Text
    ${Function:Update-PackageManagement}.Ast.Extent.Text
    ${Function:Update-SystemPathNow}.Ast.Extent.Text
)

# SIG # Begin signature block
# MIIMaAYJKoZIhvcNAQcCoIIMWTCCDFUCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUKXb2eSKLhP8W1EIKYFvbMAPH
# nFKgggndMIIEJjCCAw6gAwIBAgITawAAAERR8umMlu6FZAAAAAAARDANBgkqhkiG
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
# BDEWBBRpu6y6gg/sKPkzlZ3dXzhD85vRnjANBgkqhkiG9w0BAQEFAASCAQBeSMmK
# qc6xwuOeV5XwCRbf/ntLA75wvLqu4NHKS3ViuFG9Y6ejZKHbLuGTn6/XhouNXX/t
# OMs+BIxVYztzW6KmmSbeWS4hws4JQm6SGanX0s/TCIvTFQm1Vnvsk4pQGSwOxWjj
# gTGLgVxuEKk/KdsMz98OhCTQM4f0Gx9bpbNwxDuNc5QFd0DIPq75hlt6kAkdIpfF
# 6QA1H8jryAVCJnfIyrRNDF89n85c4432JJJ0kW6fow3mIVXkkgGtbWZ4OazvdwwC
# lVJXIl9bB4RSE+iLJx5WgoaxHt3hlwUz+k8MrKTv99nm5oS3YE8y6aiQ6HT4UJUr
# ROoflbyvIBSn6sPb
# SIG # End signature block
