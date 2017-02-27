                        
function Request-Module(
    [Parameter(Mandatory=$true)]
    $modules, 
    $version = $null,
    $package = $null,
    [switch][bool] $reload,
    $source = "oneget",
    [switch][bool] $wait = $false,
    [Parameter()]
    [ValidateSet("AllUsers","CurrentUser","Auto")]
    [string] $scope = "Auto"

) {
    import-module process -Global
    if ($scope -eq "Auto") {
        $scope = "CurrentUser"
        if (test-IsAdmin) { $scope = "AllUsers" }
    }

    foreach($_ in $modules)
    { 
        $currentversion = $null
        $mo = gmo $_
        $loaded = $mo -ne $null
        $found = $loaded
        if ($loaded) { $currentversion = $mo.Version[0] }
        if ($loaded -and !$reload -and ($mo.Version[0] -ge $version -or $version -eq $null)) { return }

        if (!$loaded) {
            try {
                ipmo $_ -ErrorAction SilentlyContinue -Global
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
            . "$PSScriptRoot\functions\helpers.ps1";

            if ($currentversion -ne $null) { write-host "current version of module $_ is $currentversion" }
			write-warning "module $_ version >= $version not found. installing from $source"
            if ($source -eq "choco" -or $source.startswith("choco:")) {
                if ($mo -eq $null) {
					$cmd = "invoke choco install -y $package -verbose"
					if ($source.startswith("choco:")) {
						$customsource = $source.substring("choco:".length)
						$cmd = "invoke choco install -y $package -source $customsource -verbose"
					}
                    # ensure choco is installed, then install package
                    run-AsAdmin -ArgumentList @("-Command", "
                        try {
                        . '$PSScriptRoot\functions\helpers.ps1';
                        write-host 'Ensuring chocolatey is installed';
                        _ensure-choco;
                        write-host 'installing chocolatey package $package';
                        $cmd;
                        } finally {
                            if (`$$wait) { Read-Host 'press Enter to close  this window and continue'; }
                        }
                    ") -wait
                                        
                    #refresh PSModulePath
                    refresh-modulepath 
                    $mo = gmo $_ -ListAvailable
                    # throw "Module $_ not found. `r`nSearched paths: $($env:PSModulePath)"
                }
                elseif ($mo.Version[0] -lt $version) {
                    write-warning "requested module $_ version $version, but found $($mo.Version[0])!"
                    # ensure choco is installed, then upgrade package
                    $cmd = "invoke choco upgrade -y $package -verbose"
                    if ($source.startswith("choco:")) {
						$customsource = $source.substring("choco:".length)
						$cmd = "invoke choco upgrade -y $package -source $customsource -verbose"
					}
                    run-AsAdmin -ArgumentList @("-Command", "
                        try {       
                        `$ex = `$null;              
                        . '$PSScriptRoot\functions\helpers.ps1';
                        write-host 'Ensuring chocolatey is installed';
                        _ensure-choco;
                        write-host 'updating chocolatey package $package';
                        $cmd;
                        
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
                     
                    refresh-modulepath 
                    $mo = gmo $_ -ListAvailable
                }
            }
            if ($source -in "oneget","psget","powershellget","psgallery") {
                write-warning "trying powershellget package manager"
                if ((get-command Install-PackageProvider -module PackageManagement -ErrorAction Ignore) -ne $null) {
                    import-module PackageManagement
                    $nuget = get-packageprovider -Name Nuget -force -forcebootstrap
                    if ($nuget -eq $null) {
                        write-host "installing nuget package provider"
                        # this isn't availalbe in the current official release of oneget (?)
                        install-packageprovider -Name NuGet -Force -MinimumVersion 2.8.5.201 -verbose
                    } 
                }
                import-module powershellget
                Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
                
                if ($mo -eq $null) {
                    write-warning "install-module $_ -verbose"
                    if ($scope -eq "CurrentUser") {
                        if (((get-command install-module).Parameters.AllowClobber) -ne $null) {
                            install-module $_ -verbose -scope $scope -ErrorAction stop -AllowClobber
                        } else {
                            install-module $_ -verbose -scope $scope -ErrorAction stop
                        }
                    } else {
                        if (((get-command install-module).Parameters.AllowClobber) -ne $null) {
                            run-AsAdmin -ArgumentList @("-Command", "install-module $_ -verbose -scope $scope -ErrorAction stop -AllowClobber") -wait
                        } else {
                            run-AsAdmin -ArgumentList @("-Command", "install-module $_ -verbose -scope $scope -ErrorAction stop") -wait
                        }
                    }
                }            
                else {
                    # remove module to avoid loading multiple versions
                    write-warning "update-module $_ -verbose scope:$scope"                    
                    rmo $_ -erroraction Ignore
                    $toupdate = $_
                    if ($scope -eq "CurrentUser") {
                        try {             
                            if (((get-command update-module).Parameters.AllowClobber) -ne $null) {    
                                update-module $toupdate -verbose -erroraction stop
                            } else {
                                update-module $toupdate -verbose -erroraction stop
                            }
                        } catch {
                            write-warning "need to update module as admin"
                            # if module was installed as Admin, try to update as admin
                            run-AsAdmin -ArgumentList @("-Command", "update-module $toupdate -verbose -ErrorAction stop") -wait    
                        }
                    } else {
                        run-AsAdmin -ArgumentList @("-Command", "update-module $toupdate -verbose -ErrorAction stop") -wait
                    }
                }
                $mo = gmo $_ -ListAvailable | select -first 1   
                
                if ($mo -ne $null -and $mo.Version[0] -lt $version) {
                    # ups, update-module did not succeed?
                    # if module is already installed, oneget will try to update from same repositoty
                    # if the repository has changed, we need to force install 

                    write-warning "requested module $_ version $version, but found $($mo.Version[0])!"
                    write-warning "trying again: install-module $_ -verbose -force -scope $scope"
                    if ($scope -eq "CurrentUser") {
                        if (((get-command install-module).Parameters.AllowClobber) -ne $null) {
                            install-module $_ -scope $scope -verbose -Force -ErrorAction stop -AllowClobber
                        }
                        else {
                            install-module $_ -scope $scope -verbose -Force -ErrorAction stop
                        }
                    } else {                        
                        if (((get-command install-module).Parameters.AllowClobber) -ne $null) { 
                            run-AsAdmin -ArgumentList @("-Command", "install-module $_ -scope $scope -verbose -Force -ErrorAction stop -AllowClobber") -wait
                        } else {
                            run-AsAdmin -ArgumentList @("-Command", "install-module $_ -scope $scope -verbose -Force -ErrorAction stop") -wait
                        }
                    }  
                    $mo = gmo $_ -ListAvailable    
                }

                if ($mo -eq $null) { 
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

        Import-Module $_ -DisableNameChecking -MinimumVersion $version -Global -ErrorAction stop
        }
}


if ((get-alias Require-Module -ErrorAction ignore) -eq $null) { new-alias Require-Module Request-Module }
if ((get-alias req -ErrorAction ignore) -eq $null) { new-alias req Request-Module }

Export-ModuleMember -Function "Request-Module" -Alias *