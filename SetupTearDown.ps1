<#
.SYNOPSIS
    Set up (or clean up) PSRemoting on this computer. Setup up option will enable OpenSSH Server, Firewall and setup the machine to be able to run ps commands programmatically
    Cleanup up option will disbable OpenSSH Server and perform other tasks that were done during setup like disable ufw firewall, delete remoting specific firewall rules, etc.

.PARAMETER Setup
    This Switch will trigger the setup calls which ends up starting the OpenSSH Server service and enable powershell remoting via SSH and opens up remoting via the firewall

.PARAMETER Cleanup
    This switch triggers the cleanup path which disables OpenSSH Server, removes the firewall rules that were created earlier for remoting

.PARAMETER Password
    Required Parameter. Get the password of this computer to modify firewall permissions and get OpenSSH Server.
.DESCRIPTION
    Run this script to setup your machine for PS Remoting so that you can leverage the functionality of runPerfTool.psm1
    Run this script at the end of the tool runs to restore state on the machines.
    Ex: SetupTearDown.ps1 -Setup or SetupTearDown.ps1 -Cleanup
#>
Param(
    [switch] $Setup,
    [switch] $Cleanup,
    [Parameter(Mandatory=$True, Position=0, HelpMessage="Machine Password?")]
    [SecureString]$Password
)

Function SetupRemoting{
    param(
        [Parameter(Mandatory=$True)] [PSCredential] $Creds
    )

    Write-Host "Installing PSRemoting via SSH on this computer..."
    # Write-Host "Installing Open-SSH Server"
    # Write-Output $Creds.GetNetworkCredential().Password | sudo -S apt-get update -y | Out-Null 
    # sudo apt-get install openssh-server -y | Out-Null  
    Write-Host "Editing sshd_config file to allow for public key and password authentication for port 5985"
    sudo sed -i "s/#\?\(PubkeyAuthentication\s*\).*$/\1yes/" /etc/ssh/sshd_config
    sudo sed -i 's/#\?\(PasswordAuthentication\s*\).*$/\1yes/' /etc/ssh/sshd_config
    sudo sed -i 's/#\?\(Port\s*\).*$/\15985/' /etc/ssh/sshd_config
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
    sudo service sshd restart | Out-Null 
    Write-Host "Enabling firewall and allowing ssh service from port 5985"
    sudo ufw enable | Out-Null 
    sudo ufw allow ssh | Out-Null 
    sudo ufw allow 5985/tcp | Out-Null 
} # SetupRemoting()


Function CleanupRemoting{
    param(
        [Parameter(Mandatory=$True)] [PSCredential] $Creds
    )
    Write-Host "Disabling PSRemoting via SSH on this computer..."
    Write-Host "Editing sshd_config file to allow for public key and password authentication to default port"
    sudo sed -i 's/#\?\(Port\s*\).*$/\122/' /etc/ssh/sshd_config
    sudo service sshd restart | Out-Null 
    Write-Host "Stopping Open-SSH Server service"
    Write-Output $Creds.GetNetworkCredential().Password | sudo service ssh stop | Out-Null 
    Write-Host "Deleting firewall rule that allows ssh service from port 5985"
    sudo ufw delete allow 5985/tcp | Out-Null 
    sudo ufw delete allow ssh | Out-Null 
} # CleanupRemoting()

#Main-function
function main {
    try {
        [PSCredential] $creds = New-Object System.Management.Automation.PSCredential("user", $Password)
        if($Setup.IsPresent) {
            SetupRemoting -Creds $creds
        } elseif($Cleanup.IsPresent) {
            CleanupRemoting -Creds $creds
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
