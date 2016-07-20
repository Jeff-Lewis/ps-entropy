

function Request-Module(
    [Parameter(Mandatory=$true)]
    $modules, 
    $version = $null,
    $package = $null,
    [switch][bool] $reload,
    $source = "oneget",
    [switch][bool] $wait = $false

) {
    import-module process

    foreach($_ in $modules)
    { 
        $mo = gmo $_
        $loaded = $mo -ne $null
        $found = $loaded
        if ($loaded -and !$reload -and ($mo.Version[0] -ge $version -or $version -eq $null)) { return }

        if (!$loaded) {
            try {
                ipmo $_ -ErrorAction SilentlyContinue
                $mo = gmo $_
                $loaded = $mo -ne $null
                $found = $loaded
            } catch {
            }
        }
        if(!$found) {
            $mo = gmo $_ -ListAvailable
        }
        $found = $mo -ne $null -and $mo.Version[0] -ge $version
        if ($reload -or ($version -ne $null -and $mo -ne $null -and $mo.Version[0] -lt $version)) {
            if (gmo $_) { rmo $_ }
        }

        if (!$found) {
			write-warning "module $_ version >= $version not found. installing from $source"
            if ($source -eq "choco") {
                if (!($mo)) {
                    run-AsAdmin -ArgumentList @("-Command", "
                        try {
                        . '$PSScriptRoot\Setup-Helpers.ps1';
                        write-host 'Ensuring chocolatey is installed';
                        ensure-choco;
                        write-host 'installing chocolatey package $package';
                        choco install -y $package;
                        } finally {
                            if (`$$wait) { Read-Host 'press Enter to close  this window and continue'; }
                        }
                    ") -wait

                    throw "Module $_ not found. `r`nSearched paths: $($env:PSModulePath)"
                    $mo = gmo $_ -ListAvailable
                }
                if ($mo.Version[0] -lt $version) {
                    write-warning "requested module $_ version $version, but found $($mo.Version[0])!"
                    run-AsAdmin -ArgumentList @("-Command", "
                        try {       
                        `$ex = `$null;              
                        . '$PSScriptRoot\Setup-Helpers.ps1';
                        write-host 'Ensuring chocolatey is installed';
                        ensure-choco;
                        write-host 'updating chocolatey package $package';
                        choco update $package;
                        
                        if (`$$wait) { Read-Host 'press Enter to close  this window and continue' }
                        
                        } catch {
                            write-error `$_;
                            `$ex = `$_;
                            if (`$$wait) { Read-Host 'someting went wrong. press Enter to close this window and continue' }
                            throw;
                        }
                        finally {
                        }
                    ") -wait    
                    $mo = gmo $_ -ListAvailable        
                }
            }
            if ($source -in "oneget","psget","powershellget","psgallery") {
                write-warning "trying powershellget package manager"
                if ((get-command Install-PackageProvider -module PackageManagement -ErrorAction Ignore) -ne $null) {
                    import-module PackageManagement
                    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
                }
                import-module powershellget
                Set-PSRepository -Name PSGallery -InstallationPolicy Trusted

                
                if ($mo -eq $null) {
                    write-host "install-module $_ -verbose"
                    run-AsAdmin -ArgumentList @("-Command", "install-module $_ -verbose")
                }            
                else {
                    run-AsAdmin -ArgumentList @("-Command", "update-module $_ -verbose")
                    update-module $_ -verbose
                }
                $mo = gmo $_ -ListAvailable    
                
                if ($mo -ne $null -and $mo.Version[0] -lt $version) {
                    # if module is already installed, oneget will try to update from same repositoty
                    # if the repository has changed, we need to force install 

                    write-warning "requested module $_ version $version, but found $($mo.Version[0])!"
                    write-warning "try again: install-module $_ -verbose -force"
                    run-AsAdmin -ArgumentList @("-Command", "install-module $_ -verbose -Force")  
                    $mo = gmo $_ -ListAvailable    
                }

                if ($mo -eq $null){ 
                    Write-Warning "failed to install module $_ through oneget"
                    Write-Warning "available modules:"
                    $list = find-module $_
                    $list
                } elseif ($mo.Version[0] -lt $version) {
                    Write-Warning "modules found:"
                    $m = find-module $_
                    $m | Format-Table | Out-String | Write-Warning                    
                    Write-Warning "sources:"
                    $s = Get-PackageSource
                    $s | Format-Table | Out-String | Write-Warning
                }   
            }
        }

        $found = $mo -ne $null -and $mo.Version[0] -ge $version
               
        if (!($mo)) {          
            throw "Module $_ not found. `r`nSearched paths: $($env:PSModulePath)"
        }
        if ($mo.Version[0] -lt $version) {
            throw "requested module $_ version $version, but found $($mo.Version[0])!"
        }

        Import-Module $_ -DisableNameChecking -MinimumVersion $version
        }
}

New-Alias Require-Module Request-Module
New-Alias req Request-Module

Export-ModuleMember -Function * -Alias *