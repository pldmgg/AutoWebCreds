@{
    # Some defaults for all dependencies
    PSDependOptions = @{
        Target = '$ENV:USERPROFILE\Documents\WindowsPowerShell\Modules'
        AddToPath = $True
    }

    # Grab some modules without depending on PowerShellGet
    'Selenium' = @{
        DependencyType  = 'PSGalleryNuget'
        Version         = 'Latest'
        PSVersion       = "PSCore"
    }

    'CredentialManager' = @{
        DependencyType  = 'PSGalleryNuget'
        Version         = 'Latest'
        PSVersion       = "WinPS"
    }

    'AnyBox' = @{
        DependencyType  = 'PSGalleryNuget'
        Version         = 'Latest'
        PSVersion       = "WinPS"
    }
}
