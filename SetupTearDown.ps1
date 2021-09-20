<#
.SYNOPSIS
    Set up (or clean up) PSRemoting on this computer. Setup up option will enable OpenSSH Server, Firewall and setup the machine to be able to run ps commands programmatically
    Cleanup up option will disbable OpenSSH Server and perform other tasks that were done during setup like disable ufw firewall, delete remoting specific firewall rules, etc.

.PARAMETER Setup
    This Switch will trigger the setup calls which ends up starting the OpenSSH Server service and enable powershell remoting via SSH and opens up remoting via the firewall

.PARAMETER Cleanup
    This switch triggers the cleanup path which disables OpenSSH Server, removes the firewall rules that were created earlier for remoting

.PARAMETER Port
    The port that the SSH Server will listen on. Default is 5985. 

.PARAMETER Password
    Required Parameter. Get the password of this computer to modify firewall permissions.

.PARAMETER PassAuth
    Required Parameter. Get the password of this computer to modify firewall permissions.

    .DESCRIPTION
    Run this script to setup your machine for PS Remoting so that you can leverage the functionality of runPerfTool.psm1
    Run this script at the end of the tool runs to restore state on the machines.
    Ex: SetupTearDown.ps1 -Setup or SetupTearDown.ps1 -Cleanup
#>
Param(
    [switch] $Setup,
    [switch] $Cleanup,
    [Parameter(Mandatory=$False)]  $Port=5985,
    [Parameter(Mandatory=$False)] [bool] $PassAuth
)

Function SetupRemoting{
    param(
        [Parameter(Mandatory=$False)]  $Port=5985, 
        [Parameter(Mandatory=$False)] [bool] $PassAuth
    )

    Write-Host "Installing PSRemoting via SSH on this computer..."
    Write-Host "Editing sshd_config file to allow for public key and password authentication for port $Port"
    # edit sshd_config to listen to port and allow public key and password authentication
    sudo -S sed -i "s/#\?\(PubkeyAuthentication\s*\).*$/\1yes/" /etc/ssh/sshd_config
    if ($PassAuth) 
    {
        sudo sed -i 's/#\?\(PasswordAuthentication\s*\).*$/\1yes/' /etc/ssh/sshd_config
    }
    sudo sed -i "s/#\?\(Port\s*\).*$/\1$Port/" /etc/ssh/sshd_config
    # allow for powershell remoting via ssh 
    $pwshCommand = Get-Content -Path /etc/ssh/sshd_config | Where-Object {$_.Contains("Subsystem powershell /usr/bin/pwsh -sshs -NoLogo")}
    if ([string]::IsNullOrEmpty($pwshCommand)) {
        if (Test-Path -Path /usr/bin/pwsh) {
            Write-Output "Subsystem powershell /usr/bin/pwsh -sshs -NoLogo" | sudo tee -a /etc/ssh/sshd_config | Out-Null 
        } else {
            $pwshPath = which pwsh
            Write-Output "Subsystem powershell $pwshPath -sshs -NoLogo" | sudo tee -a /etc/ssh/sshd_config | Out-Null 
        }
    }
    Write-Host "Starting OpenSSH Server"
    # restart ssh server
    sudo service sshd restart | Out-Null 
    Write-Host "Enabling firewall and allowing ssh service from port $Port"
    # enable ssh server and listening port
    sudo ufw enable | Out-Null 
    sudo ufw allow ssh | Out-Null 
    sudo ufw allow $Port/tcp | Out-Null 
} # SetupRemoting()


Function CleanupRemoting{
    param(
        [Parameter(Mandatory=$False)]  $Port=5985
    )
    Write-Host "Disabling PSRemoting via SSH on this computer..."
    Write-Host "Editing sshd_config file to allow for public key and password authentication to default port"
    # edit ssh server to listen to default port of 22
    sudo -S sed -i 's/#\?\(Port\s*\).*$/\122/' /etc/ssh/sshd_config
    # restart and stop sshd server 
    sudo service sshd restart | Out-Null 
    Write-Host "Stopping Open-SSH Server service"
    sudo service sshd stop | Out-Null 
    # delete ssh and port firewall rules
    Write-Host "Deleting firewall rule that allows ssh service from port $Port"
    sudo ufw delete allow $Port/tcp | Out-Null 
    sudo ufw delete allow ssh | Out-Null 
} # CleanupRemoting()

#Main-function
function main {
    try {
        # create credential blob to store username and password securely 
        if($Setup.IsPresent) {
            SetupRemoting -Port $Port -PassAuth $PassAuth
        } elseif($Cleanup.IsPresent) {
            CleanupRemoting -Port $Port
        } else {
            Write-Host "Exiting.. as neither the setup nor cleanup flag was passed"
        }
    } # end try
    catch {
       Write-Host "Exception $($_.Exception.Message) in $($MyInvocation.MyCommand.Name)"
    }    
}

#Entry point
main @PSBoundParameters
