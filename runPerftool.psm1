$computername = hostname
$Logfile = "./$computername.log"
Clear-content -Path $Logfile -Force -ErrorAction Ignore

#Function to write to log file
Function LogWrite
{
Param ([string]$logstring, [string] $echoToConsole=$false)
    $timeStampLogString = "[{0}] {1}"-f (Get-Date -Format "MM/dd/yyyy HH:mm"), $logstring
    if ($echoToConsole -eq $true) {
        Write-Host $timeStampLogString
    }
    Add-content $Logfile -value $timeStampLogString
}

# Certain tools like ntttcp have params that need to be added to the actual timeout value between command pairs
# to prevent premature termination of the send/recv processes
Function GetActualTimeOutValue
{
Param ([Int]$AdditionalTimeout, [string] $Line)

    [Int] $timeout = $AdditionalTimeout 
    # currently we only bloat the timeout value with additional params for ntttcp. 
    # as we onboard additional tools in the future, we will add tool specific logic here
    if ($Line -match "ntttcp")
    {
        try {
            [Int] $warmup = ($Line.Substring($Line.IndexOf("-W")+("-W".Length)+1).Split(' ')[0])
            [Int] $cooldown = ($Line.Substring($Line.IndexOf("-C")+("-C".Length)+1).Split(' ')[0])
            [Int] $runtime = ($Line.Substring($Line.IndexOf("-t")+("-t".Length)+1).Split(' ')[0])
            $timeout += $warmup + $cooldown + $runtime
        }
       catch {}
    }
    elseif ($Line -match "secnetperf") {
        try {
            $runtime = 0
            if ($Line.Contains("-run")) {
                [Int] $runtime = [Int]($Line.Substring($Line.IndexOf("-run")).Split(" ")[0].Split(":")[1] -replace '[^0-9]')
            } elseif ($Line.Contains("-up") -or $Line.Contains("-down")) {
                [Int] $runtime = [Int]($Line.Substring($Line.IndexOf("-up")).Split(" ")[0].Split(":")[1] -replace '[^0-9]')
                $runtime += [Int]($Line.Substring($Line.IndexOf("-down")).Split(" ")[0].Split(":")[1] -replace '[^0-9]')
            }
            return $runtime
        }
        catch {}
    }
    return $timeout
}
#===============================================
# Scriptblock Util functions
#===============================================

$ScriptBlockEnableToolPermissions = {
    param ($remoteToolPath)
    chmod 777 $remoteToolPath
} # $ScriptBlockEnableToolPermissions()

$ScriptBlockMoveLibrary = {
    param ($remoteToolPath, $creds)
    if ([String]::IsNullOrWhiteSpace($creds.GetNetworkCredential().Password)) {
        sudo mv $remoteToolPath /usr/local/lib
    } else {
        Write-Output $creds.GetNetworkCredential().Password | mv $remoteToolPath /usr/local/lib
    }
    sudo ldconfig
} # $ScriptBlockMoveLibrary()

$ScriptBlockCleanupFirewallRules = {
    param($port, $creds)
    
    $hasUfw = $(dpkg --get-selections | grep ufw)
    if ($null -eq $hasUfw) {
        Write-Host 'Ufw is not installed'
    }
    elseif ([String]::IsNullOrWhiteSpace($creds.GetNetworkCredential().Password)) {
        sudo ufw delete allow $port | Out-Null
    } else {
        Write-Output $creds.GetNetworkCredential().Password | sudo -S ufw delete allow $port | Out-Null
    }
 } # $ScriptBlockCleanupFirewallRules()

$ScriptBlockEnableFirewallRules = {
    param ($port, $creds)

    $hasUfw = $(dpkg --get-selections | grep ufw)
    if ($null -eq $hasUfw) {
        Write-Host 'Ufw is not installed'
    }
    elseif ([String]::IsNullOrWhiteSpace($creds.GetNetworkCredential().Password)) {
        sudo ufw allow $port | Out-Null
    } else {
        Write-Output $creds.GetNetworkCredential().Password | sudo -S ufw allow $port | Out-Null
    }
 } # $ScriptBlockEnableFirewallRules()

$ScriptBlockTaskKill = {
    param ($taskname)
    $taskStatus = pidof $taskname
    if (![string]::IsNullOrEmpty($taskStatus)) {
        killall $taskname | Out-Null
    }
} # $ScriptBlockTaskKill()

# Set up a directory on the remote machines for results gathering.
$ScriptBlockCreateDirForResults = {
    param ($Cmddir)
    if (!(Test-Path $Cmddir)) {
        New-Item -ItemType Directory -Force -Path "$Cmddir" | Out-Null
    }
    return $Exists
} # $ScriptBlockCreateDirForResults()


# Delete file/folder on the remote machines 
$ScriptBlockRemoveFileFolder = {
    param ($Arg)
    Remove-Item -Force -Path "$Arg" -Recurse -ErrorAction SilentlyContinue
} # $ScriptBlockRemoveFileFolder()

# Delete file/folder on the remote machines 
$ScriptBlockIsArm64 = {
    param ()
    $Output = uanme -m
    if ($Output -contains 'aarch64') {
        return $true
    }
    return $false
} # $ScriptBlockIsArm64()


# Delete the entire folder (if empty) on the remote machines
$ScriptBlockRemoveFolderTree = {
    param ($Arg)

    $parentfolder = (Get-Item $Arg).Parent.FullName

    # First do as instructed. Remove-Item $arg.
    Remove-Item -Force -Path "$Arg" -Recurse -ErrorAction SilentlyContinue

    # We dont know how many levels of parent folders were created so we will keep navigating upward till we find a non empty parent directory and then stop
    $folderCount = $parentfolder.Split('/').count 

    for ($i=1; $i -le $folderCount; $i++) {

        $folderToDelete = $parentfolder

        #Extract parent info before nuking the folder
        $parentfolder = (Get-Item $folderToDelete).Parent.FullName

           
        #check if the folder is empty and if so, delete it
        if ((dir -Directory $folderToDelete | Measure-Object).Count -eq 0) {
            Remove-Item -Force -Path "$folderToDelete" -Recurse -ErrorAction SilentlyContinue
        }
        else
        { 
            #Folder/subfolder wasnt found empty. so we stop here and exit
            break
        }

    }

} # $ScriptBlockRemoveFolderTree ()

$ScriptBlockCreateZip = {
    Param(
        [String] $Src,
        [String] $Out
    )

    if (Test-path $Out) {
        Remove-item $Out 
    }

    zip -r $Out $Src | Out-Null
} # $ScriptBlockCreateZip()

$ScriptBlockRemoveAuthorizedHost = {
    head -n -1 ".ssh/authorized_keys" | Out-Null
} # $ScriptBlockRemoveAuthorizedHost

$ScriptBlockRemoveBinaries = {
    param($remoteToolPath)
    Remove-Item -Path $remoteToolPath -Force -ErrorAction SilentlyContinue
} # $ScriptBlockRemoveBinaries

<#
.SYNOPSIS
    This function reads an input file of commands and orchestrates the execution of these commands on remote machines.

.PARAMETER DestIp
    Required Parameter. The IpAddr of the destination machine that's going to receive data for the duration of the throughput tests

.PARAMETER SrcIp
    Required Parameter. The IpAddr of the source machine that's going to be sending data for the duration of the throughput tests

.PARAMETER PassAuth
    Boolean. Set to true if using password authentication to connect to machines

.PARAMETER DestIpUserName
    Required Parameter. Gets domain\username needed to connect to DestIp Machine

.PARAMETER DestIpPassword
    Required Parameter. Gets password needed to connect to DestIp Machine. 
    Password will be stored as Secure String and chars will not be displayed on the console.

.PARAMETER DestIpKeyPath
    File path to private rsa key needed to connect to DestIp Machine. Only required if -PassAuth is false.

.PARAMETER SrcIpUserName
    Required Parameter. Gets domain\username needed to connect to SrcIp Machine

.PARAMETER SrcIpPassword
    Required Parameter. Gets password needed to connect to SrcIp Machine. 
    Password will be stored as Secure String and chars will not be displayed on the console

.PARAMETER SrcIpKeyPath
    File path to private rsa key needed to connect to SrcIp Machine. Only required if -PassAuth is false.

.PARAMETER TestUserName
    Required Parameter. Gets username of current machine to get correct path to commands 

.PARAMETER CommandsDir
    Required Parameter that specifies the location of the folder with the auto generated commands to run.

.PARAMETER BCleanup
    Optional parameter that will clean up the source and destination folders, after the test run, if set to true.
    If false, the folders that were created to store the results will be left untouched on both machines
    Default value: $True

.PARAMETER ZipResults
    Optional parameter that will compress the results folders before copying it over to the machine that's triggering the run.
    If false, the result folders from both Source and Destination machines will be copied over as is.
    Default value: $True

.PARAMETER TimeoutValueInSeconds
    Optional parameter to configure the amount of wait time (in seconds) to allow each command pair to gracefully exit 
    before cleaning up and moving to the next set of commands
    Default value: 90 seconds

.PARAMETER PollTimeInSeconds
    Optional parameter to configure the amount of time the tool waits (in seconds) before waking up to check if the TimeoutValueBetweenCommandPairs period has elapsed
    Default value: 5

.PARAMETER ListeningPort
    Optional port number that the recevier and sender computer SSH server is listening on from Setup script.
    Default value: 5985

.PARAMETER FirewallPortMin
    Optional minimum server port number used for iteration tests to allow firewall to accept pings from
    Default value: 50000

.PARAMETER FirewallPortMax
    Optional maximum server port number used for iteration tests to allow firewall to accept pings from
    Default value: 50512

.DESCRIPTION
    Please run SetupTearDown.ps1 -Setup on the DestIp and SrcIp machines independently to help with PSRemoting setup
    This function is dependent on the output of PERFTEST.PS1 function
    for example, PERFTEST.PS1 is invoked with DestIp, SrcIp and OutDir.
    to invoke the commands that were generated above, we pass the same parameters to ProcessCommands function
    Note that we expect the directory to be pointing to the folder that was generated by perftest.ps1 under the outpurDir path supplied by the user
    Ex: ProcessCommands -DestIp "$DestIp" -SrcIp "$SrcIp" -CommandsDir "temp/msdbg.Machine1.perftest" -DestIpUserName "domain\username" -SrcIpUserName "domain\username"
    You may chose to run SetupTearDown.ps1 -Cleanup if you wish to clean up any config changes from the Setup step
#>
Function ProcessCommands{
    param(
    [Parameter(Mandatory=$True)]  [string]$DestIp,
    [Parameter(Mandatory=$True)] [string]$SrcIp,
    [Parameter(Mandatory=$True)]  [string]$CommandsDir,
    [Parameter(ParameterSetName='PassAuth', Mandatory=$False)]  [bool]$PassAuth = $False,
    [Parameter(Mandatory=$True, Position=0, HelpMessage="Dest Machine Username?")]
    [string] $DestIpUserName,
    [Parameter(ParameterSetName='PassAuth', Mandatory=$False, Position=0, HelpMessage="Dest Machine Password?")]
    [SecureString]$DestIpPassword,
    [Parameter(Mandatory=$False, Position=0, HelpMessage="Dest Machine Key File?")]
    [String]$DestIpKeyFile = "",
    [Parameter(Mandatory=$True, Position=0, HelpMessage="Src Machine Username?")]
    [string] $SrcIpUserName,
    [Parameter(ParameterSetName='PassAuth', Mandatory=$False, Position=0, HelpMessage="Src Machine Password?")]
    [SecureString]$SrcIpPassword,
    [Parameter(Mandatory=$False, Position=0, HelpMessage="Src Machine Key File?")]
    [String]$SrcIpKeyFile = "",
    [Parameter(Mandatory=$True, Position=0, HelpMessage="Test Machine Username?")]
    [string] $TestUserName,
    [Parameter(Mandatory=$False)] [string]$Bcleanup=$True,
    [Parameter(Mandatory=$False)]$ZipResults=$True,
    [Parameter(Mandatory=$False)]$TimeoutValueInSeconds=90,
    [Parameter(Mandatory=$False)]$PollTimeInSeconds=5,
    [Parameter(Mandatory=$False)] [int] $ListeningPort = 5985,
    [Parameter(Mandatory=$False)] [int] $FirewallPortMin = 50000,
    [Parameter(Mandatory=$False)] [int] $FirewallPortMax = 50512
    )

    $recvComputerName = $DestIp
    $sendComputerName = $SrcIp

    $recvDir = "/home/$DestIpUserName/$CommandsDir"
    $sendDir = "/home/$SrcIpUserName/$CommandsDir"
    $CommandsDir = "/home/$TestUserName/$CommandsDir"

    # create password placeholder
    if ($SrcIpPassword -eq $null) {
        $SrcIpPassword = ConvertTo-SecureString -String ' ' -AsPlainText -Force
    }

    # create password placeholder
    if ($DestIpPassword -eq $null) {
        $DestIpPassword = ConvertTo-SecureString -String ' ' -AsPlainText -Force
    }

    [PSCredential] $sendIPCreds = New-Object System.Management.Automation.PSCredential($SrcIpUserName, $SrcIpPassword)

    [PSCredential] $recvIPCreds = New-Object System.Management.Automation.PSCredential($DestIpUserName, $DestIpPassword)

    if (Test-Path -Path "$commandsDir\lagscope") {
        LogWrite "Processing lagscope commands for Linux" $true
        ProcessToolCommands -PassAuth:$PassAuth -RecvKeyFilePath $DestIpKeyFile -SendKeyFilePath $SrcIpKeyFile -Toolname "lagscope" -RecvComputerName $recvComputerName -RecvComputerCreds $recvIPCreds -SendComputerName $sendComputerName -SendComputerCreds $sendIPCreds -TestUserName $TestUserName -CommandsDir $CommandsDir -Bcleanup $Bcleanup -BZip $ZipResults -TimeoutValueBetweenCommandPairs $TimeoutValueInSeconds -PollTimeInSeconds $PollTimeInSeconds -ListeningPort $ListeningPort -FirewallPortMin $FirewallPortMin -FirewallPortMax $FirewallPortMax -RecvDir $recvDir -SendDir $sendDir
    }

    if (Test-Path -Path "$commandsDir\ntttcp") {
        LogWrite "Processing ntttcp commands for Linux" $true
        ProcessToolCommands -PassAuth $PassAuth -RecvKeyFilePath $DestIpKeyFile -SendKeyFilePath $SrcIpKeyFile -Toolname "ntttcp" -RecvComputerName $recvComputerName -RecvComputerCreds $recvIPCreds -SendComputerName $sendComputerName -SendComputerCreds $sendIPCreds -TestUserName $TestUserName -CommandsDir $CommandsDir -Bcleanup $Bcleanup -BZip $ZipResults -TimeoutValueBetweenCommandPairs $TimeoutValueInSeconds -PollTimeInSeconds $PollTimeInSeconds -ListeningPort $ListeningPort -FirewallPortMin $FirewallPortMin -FirewallPortMax $FirewallPortMax -RecvDir $recvDir -SendDir $sendDir
    }

    if (Test-Path -Path "$commandsDir\ncps") {
        LogWrite "Processing ncps commands for Linux" $true
        ProcessToolCommands -PassAuth $PassAuth -RecvKeyFilePath $DestIpKeyFile -SendKeyFilePath $SrcIpKeyFile -Toolname "ncps" -RecvComputerName $recvComputerName -RecvComputerCreds $recvIPCreds -SendComputerName $sendComputerName -SendComputerCreds $sendIPCreds -TestUserName $TestUserName -CommandsDir $CommandsDir -Bcleanup $Bcleanup -BZip $ZipResults -TimeoutValueBetweenCommandPairs $TimeoutValueInSeconds -PollTimeInSeconds $PollTimeInSeconds -ListeningPort $ListeningPort -FirewallPortMin $FirewallPortMin -FirewallPortMax $FirewallPortMax -RecvDir $recvDir -SendDir $sendDir
    }

    if (Test-Path -Path "$commandsDir\secnetperf") {
        LogWrite "Processing secnetperf commands for Linux" $true
        ProcessToolCommands -PassAuth $PassAuth -RecvKeyFilePath $DestIpKeyFile -SendKeyFilePath $SrcIpKeyFile -Toolname "secnetperf" -RecvComputerName $recvComputerName -RecvComputerCreds $recvIPCreds -SendComputerName $sendComputerName -SendComputerCreds $sendIPCreds -TestUserName $TestUserName -CommandsDir $CommandsDir -Bcleanup $Bcleanup -BZip $ZipResults -TimeoutValueBetweenCommandPairs $TimeoutValueInSeconds -PollTimeInSeconds $PollTimeInSeconds -ListeningPort $ListeningPort -FirewallPortMin $FirewallPortMin -FirewallPortMax $FirewallPortMax -RecvDir $recvDir -SendDir $sendDir
    }

    if (Test-Path -Path "$commandsDir\l4ping") {
        LogWrite "Processing l4ping commands for Linux" $true
        ProcessToolCommands -PassAuth $PassAuth -RecvKeyFilePath $DestIpKeyFile -SendKeyFilePath $SrcIpKeyFile -Toolname "l4ping" -RecvComputerName $recvComputerName -RecvComputerCreds $recvIPCreds -SendComputerName $sendComputerName -SendComputerCreds $sendIPCreds -TestUserName $TestUserName -CommandsDir $CommandsDir -Bcleanup $Bcleanup -BZip $ZipResults -TimeoutValueBetweenCommandPairs $TimeoutValueInSeconds -PollTimeInSeconds $PollTimeInSeconds -ListeningPort $ListeningPort -FirewallPortMin $FirewallPortMin -FirewallPortMax $FirewallPortMax -RecvDir $recvDir -SendDir $sendDir
    }
    LogWrite "ProcessCommands Done!" $true
    Move-Item -Force -Path $Logfile -Destination "$CommandsDir" -ErrorAction Ignore

} # ProcessCommands()


#===============================================
# Internal Functions
#===============================================

<#
.SYNOPSIS
    This function reads an input file of commands and orchestrates the execution of these commands on remote machines.

.PARAMETER RecvComputerName
    The IpAddr of the destination machine that's going to play the Receiver role and wait to receive data for the duration of the throughput tests

.PARAMETER SendComputerName
    The IpAddr of the sender machine that's going to send data for the duration of the throughput tests

.PARAMETER PassAuth
    Boolean. Set to true if using password authentication to connect to machines

.PARAMETER TestUserName
    Required Parameter. Gets username of current machine to get correct path to commands 

.PARAMETER CommandsDir
    The location of the folder that's going to have the auto generated commands for the tool.

.PARAMETER Toolname
    Default value: ntttcp. The function parses the Send and Recv files for the tool specified here
    and reads the commands and executes them on the SrcIp and DestIp machines

.PARAMETER bCleanup
    Required parameter. The function creates folders and subfolders on remote machines to house the result files of the individual commands. bCleanup param decides 
    if the folders should be left as is, or if they should be cleaned up

.PARAMETER SendComputerCreds
    Optional PSCredentials to connect to the Sender machine

.PARAMETER RecvComputerCreds
    Optional PSCredentials to connect to the Receiver machine

.PARAMETER SendKeyFilePath
    File path to private rsa key needed to connect to Send Machine. Only required if -PassAuth is false.

.PARAMETER RecvKeyFilePath
    File path to private rsa key needed to connect to Recv Machine. Only required if -PassAuth is false.

.PARAMETER BZip
    Required parameter. The function creates folders and subfolders on remote machines to house the result files of the individual commands. BZip param decides 
    if the folders should be compressed or left uncompressed before copying over.

.PARAMETER TimeoutValueBetweenCommandPairs
    Optional parameter to configure the amount of time the tool waits (in seconds) between command pairs before moving to the next set of commands

.PARAMETER PollTimeInSeconds
    Optional parameter to configure the amount of time the tool waits (in seconds) before waking up to check if the TimeoutValueBetweenCommandPairs period has elapsed

.PARAMETER ListeningPort
    Optional port number that the recevier and sender computer SSH server is listening on from Setup script.

.PARAMETER FirewallPortMin
    Optional minimum server port number used for iteration tests to allow firewall to accept pings from

.PARAMETER FirewallPortMax
    Optional maximum server port number used for iteration tests to allow firewall to accept pings from

.PARAMETER RecvDir
    Location of folder on receiver computer that is going to have commands and store results

.PARAMETER SendDir
    Location of folder on sender computer that is going to have commands and store results

#>
Function ProcessToolCommands{
    param(
        [Parameter(Mandatory=$True)] [string]$RecvComputerName,
        [Parameter(Mandatory=$True)] [string]$SendComputerName,
        [Parameter(Mandatory=$False)] [bool]$PassAuth = $False,
        [Parameter(Mandatory=$True)] [string]$CommandsDir,
        [Parameter(Mandatory=$True)] [string]$Bcleanup, 
        [Parameter(Mandatory=$False)] [string]$Toolname = "ntttcp", 
        [Parameter(Mandatory=$False)] [PSCredential] $SendComputerCreds = [System.Management.Automation.PSCredential]::Empty,
        [Parameter(Mandatory=$False)] [PSCredential] $RecvComputerCreds = [System.Management.Automation.PSCredential]::Empty,
        [Parameter(Mandatory=$False)] [String] $SendKeyFilePath = "",
        [Parameter(Mandatory=$False)] [String] $RecvKeyFilePath = "",
        [Parameter(Mandatory=$True)] [string] $TestUserName,
        [Parameter(Mandatory=$True)] [bool]$BZip,
        [Parameter(Mandatory=$False)] [int] $TimeoutValueBetweenCommandPairs = 60,
        [Parameter(Mandatory=$False)] [int] $PollTimeInSeconds = 5,
        [Parameter(Mandatory=$False)] [int] $ListeningPort = 5985,
        [Parameter(Mandatory=$False)] [int] $FirewallPortMin = 50000,
        [Parameter(Mandatory=$False)] [int] $FirewallPortMax = 50512,
        [Parameter(Mandatory=$True)] [string]$RecvDir,
        [Parameter(Mandatory=$True)] [string]$SendDir
        )
        [bool] $gracefulCleanup = $False
        # delay to let credential (public key) propagate before remoting
        $credPropagationTimeInSecond = 3
    
        [System.IO.TextReader] $recvCommands = $null
        [System.IO.TextReader] $sendCommands = $null
    
        $toolpath = "./{0}" -f $Toolname
        $homePath = "/home/$TestUserName"

        LogWrite "Adding receiver and sender computer to known hosts"
        # add receiver and sender computer to known host of current computer
        if ((Test-Path "$homePath/.ssh") -eq $False) {
            New-Item -Path "$homePath/.ssh" -ItemType Directory
        }
        ssh-keyscan -H -p $ListeningPort $RecvComputerName >> "$homePath/.ssh/known_hosts"
        ssh-keyscan -H -p $ListeningPort $SendComputerName >> "$homePath/.ssh/known_hosts"
        try {
            if ($PassAuth) {
                $keyFilePath = "$homePath/.ssh/netperf_rsa"
                $pubKeyFilePath = "$homePath/.ssh/netperf_rsa.pub"

                $sshCommandFilePath =  "$CommandsDir/sshCommand.txt"
                if ((Test-Path $keyFilePath) -eq $False) {
                    LogWrite "Creating RSA public/private key pair"
                    # generate public and private key for ssh specific for NetPerfTest
                    Write-Output $keyFilePath | ssh-keygen --% -q -t rsa -N ""
                    chmod 600 $keyFilePath
                }
                # create command to copy public key to receiver and sender computer
                if ((Test-Path $sshCommandFilePath) -eq $True) {
                    Remove-Item -Path $sshCommandFilePath -ErrorAction SilentlyContinue -Force
                }
                Add-Content -Path $sshCommandFilePath -Value ("umask 077; test -d .ssh || mkdir .ssh ; echo `"" + (Get-Content $pubKeyFilePath) + "`" >> .ssh/authorized_keys")
                Start-Sleep -Seconds 60
                chmod 777 $sshCommandFilePath 

                # copy key over to send and recv machine
                Write-Output "n" | plink -P $ListeningPort $RecvComputerName -l $RecvComputerCreds.GetNetworkCredential().UserName -pw $RecvComputerCreds.GetNetworkCredential().Password -m $sshCommandFilePath | Out-Null
                Write-Output "n" | plink -P $ListeningPort $SendComputerName -l $SendComputerCreds.GetNetworkCredential().UserName -pw $SendComputerCreds.GetNetworkCredential().Password $sshCommandFilePath | Out-Null
                # sleep for credentials to propagate 
                start-sleep -seconds $credPropagationTimeInSecond
                $SendKeyFilePath = $keyFilePath
                $RecvKeyFilePath = $keyFilePath
            }
            #add [] to addresses if they are ipv6
            if ($RecvComputerName.Contains(":")) {
                $RecvComputerName = "[$RecvComputerName]"
            }
            $recvPSSession = New-PSSession -Port $ListeningPort -HostName $RecvComputerName -UserName ($RecvComputerCreds.GetNetworkCredential().UserName) -KeyFilePath $RecvKeyFilePath
    
            if($null -eq $recvPSsession) {
                LogWrite "Error connecting to Host: $($RecvComputerName)"
                return 
            }
    
            # Establish the Remote PS session with Sender
            if ($SendComputerName.Contains(":")) {
                $SendComputerName = "[$SendComputerName]"
            }
            $sendPSSession = New-PSSession -Port $ListeningPort -HostName $SendComputerName -UserName $SendComputerCreds.GetNetworkCredential().UserName -KeyFilePath $SendKeyFilePath
        
            if($null -eq $sendPSsession) {
                LogWrite "Error connecting to Host: $($SendComputerName)"
                return
            }
    
            # Construct the input file to read for commands.
            $ToolnameUpper = $Toolname.ToUpper()
            $sendCmdFile = Join-Path -Path $CommandsDir -ChildPath "/$Toolname/$ToolnameUpper.Commands.Send.txt"
            $recvCmdFile = Join-Path -Path $CommandsDir -ChildPath "/$Toolname/$ToolnameUpper.Commands.Recv.txt"
    
            # Ensure that remote machines have the directory created for results gathering. 
            $recvFolderExists = Invoke-Command -Session $recvPSSession -ScriptBlock $ScriptBlockCreateDirForResults -ArgumentList ($RecvDir)
            $sendFolderExists = Invoke-Command -Session $sendPSSession -ScriptBlock $ScriptBlockCreateDirForResults -ArgumentList ($SendDir)
    
            # Clean up the Receiver/Sender folders on remote machines, if they exist so that we dont capture any stale logs
            Invoke-Command -Session $recvPSSession -ScriptBlock $ScriptBlockRemoveFileFolder -ArgumentList "$RecvDir/Receiver"
            Invoke-Command -Session $sendPSSession -ScriptBlock $ScriptBlockRemoveFileFolder -ArgumentList "$SendDir/Sender"
    
            #Create dirs and subdirs for each of the supported tools
            if ($Toolname -eq 'secnetperf') {
                Invoke-Command -Session $sendPSSession -ScriptBlock $ScriptBlockCreateDirForResults -ArgumentList ($SendDir+"/Sender/$Toolname/handshakes/quic")
                Invoke-Command -Session $sendPSSession -ScriptBlock $ScriptBlockCreateDirForResults -ArgumentList ($SendDir+"/Sender/$Toolname/handshakes/tcp")
                Invoke-Command -Session $sendPSSession -ScriptBlock $ScriptBlockCreateDirForResults -ArgumentList ($SendDir+"/Sender/$Toolname/latency/quic")
                Invoke-Command -Session $sendPSSession -ScriptBlock $ScriptBlockCreateDirForResults -ArgumentList ($SendDir+"/Sender/$Toolname/latency/tcp")
                Invoke-Command -Session $sendPSSession -ScriptBlock $ScriptBlockCreateDirForResults -ArgumentList ($SendDir+"/Sender/$Toolname/throughput/quic")
                Invoke-Command -Session $sendPSSession -ScriptBlock $ScriptBlockCreateDirForResults -ArgumentList ($SendDir+"/Sender/$Toolname/throughput/tcp")
                Invoke-Command -Session $recvPSSession -ScriptBlock $ScriptBlockCreateDirForResults -ArgumentList ($RecvDir+"/Receiver/$Toolname")
            } else {
                Invoke-Command -Session $recvPSSession -ScriptBlock $ScriptBlockCreateDirForResults -ArgumentList ($RecvDir+"/Receiver/$Toolname/tcp")
                Invoke-Command -Session $sendPSSession -ScriptBlock $ScriptBlockCreateDirForResults -ArgumentList ($SendDir+"/Sender/$Toolname/tcp")
                Invoke-Command -Session $recvPSSession -ScriptBlock $ScriptBlockCreateDirForResults -ArgumentList ($RecvDir+"/Receiver/$Toolname/udp")
                Invoke-Command -Session $sendPSSession -ScriptBlock $ScriptBlockCreateDirForResults -ArgumentList ($SendDir+"/Sender/$Toolname/udp")
            }

            $ArmRecv = Invoke-Command -Session $recvPSSession -ScriptBlock $ScriptBlockIsArm64
            $ArmSend = Invoke-Command -Session $sendPSSession -ScriptBlock $ScriptBlockIsArm64

            if ($ArmRecv -and $ArmSend) {
                $toolpath = "./{0}/arm64" -f $Toolname
            }
    
            # Copy the tool binaries to the remote machines
            Copy-Item -Path "$toolpath/$Toolname" -Destination "$RecvDir/Receiver/$Toolname" -ToSession $recvPSSession
            Copy-Item -Path "$toolpath/$Toolname" -Destination "$SendDir/Sender/$Toolname" -ToSession $sendPSSession
            
            if ($Toolname -eq 'ncps') {
                Copy-Item -Path "$toolpath/vcruntime140.dll" -Destination "$RecvDir/Receiver/$Toolname" -ToSession $recvPSSession
                Copy-Item -Path "$toolpath/vcruntime140.dll" -Destination "$SendDir/Sender/$Toolname" -ToSession $sendPSSession
            } elseif ($Toolname -eq 'secnetperf') {
                Copy-Item -Path "$toolpath/libmsquic.so.2" -Destination "$RecvDir/Receiver/$Toolname" -ToSession $recvPSSession
                Copy-Item -Path "$toolpath/libmsquic.so.2" -Destination "$SendDir/Sender/$Toolname" -ToSession $sendPSSession
                Invoke-Command -Session $recvPSSession -ScriptBlock ([Scriptblock]::Create("`$env:LD_LIBRARY_PATH = $RecvDir/Receiver/$Toolname/libmsquic.so.2"))
                Invoke-Command -Session $sendPSSession -ScriptBlock ([Scriptblock]::Create("`$env:LD_LIBRARY_PATH = $SendDir/Sender/$Toolname/libmsquic.so.2"))
                Invoke-Command -Session $recvPSSession -ScriptBlock $ScriptBlockMoveLibrary -ArgumentList ("$RecvDir/Receiver/$Toolname/libmsquic.so.2", $RecvComputerCreds)
                Invoke-Command -Session $sendPSSession -ScriptBlock $ScriptBlockMoveLibrary -ArgumentList ("$SendDir/Sender/$Toolname/libmsquic.so.2", $SendComputerCreds)
            }

            # Enable execution of tool binaries 
            Invoke-Command -Session $recvPSSession -ScriptBlock $ScriptBlockEnableToolPermissions -ArgumentList "$RecvDir/Receiver/$Toolname/$Toolname"
            Invoke-Command -Session $sendPSSession -ScriptBlock $ScriptBlockEnableToolPermissions -ArgumentList "$SendDir/Sender/$Toolname/$Toolname"
            
            # allow multiple ports in firewall
            Invoke-Command -Session $recvPSSession -ScriptBlock $ScriptBlockEnableFirewallRules -ArgumentList ("$FirewallPortMin`:$FirewallPortMax/tcp", $RecvComputerCreds)
            Invoke-Command -Session $sendPSSession -ScriptBlock $ScriptBlockEnableFirewallRules -ArgumentList ("$FirewallPortMin`:$FirewallPortMax/tcp", $SendComputerCreds)
            Invoke-Command -Session $recvPSSession -ScriptBlock $ScriptBlockEnableFirewallRules -ArgumentList ("$FirewallPortMin`:$FirewallPortMax/udp", $RecvComputerCreds)
            Invoke-Command -Session $sendPSSession -ScriptBlock $ScriptBlockEnableFirewallRules -ArgumentList ("$FirewallPortMin`:$FirewallPortMax/udp", $SendComputerCreds)
            
            # Kill any background processes related to tool in case previous run is still running
            Invoke-Command -Session $recvPSSession -ScriptBlock $ScriptBlockTaskKill -ArgumentList $Toolname
            Invoke-Command -Session $sendPSSession -ScriptBlock $ScriptBlockTaskKill -ArgumentList $Toolname

            # get number of commands to run
            $commandTotal = (Get-Content $recvCmdFile | Measure-Object -Line).Lines
            $commandCount = 0
            $recvCommands = [System.IO.File]::OpenText($recvCmdFile)
            $sendCommands = [System.IO.File]::OpenText($sendCmdFile)
            $sw = [diagnostics.stopwatch]::StartNew()
    
            while(($null -ne ($recvCmd = $recvCommands.ReadLine())) -and ($null -ne ($sendCmd = $sendCommands.ReadLine()))) {
                $commandCount = $commandCount + 1
                #change the command to add path to tool
                $recvCmd =  $recvCmd -ireplace [regex]::Escape("./$Toolname"), "$RecvDir/$Toolname/$Toolname"
                $sendCmd =  $sendCmd -ireplace [regex]::Escape("./$Toolname"), "$SendDir/$Toolname/$Toolname"
                
                # Work here to invoke recv commands
                # Since we want the files to get generated under a subfolder, we replace the path to include the subfolder
                $recvCmd =  $recvCmd -ireplace [regex]::Escape($CommandsDir), "$RecvDir/Receiver"
                LogWrite "Invoking Cmd - Machine: $recvComputerName Command: $recvCmd" 
                $recvJob = Invoke-Command -Session $recvPSSession -ScriptBlock ([Scriptblock]::Create($recvCmd)) -AsJob 
                
                Start-Sleep -Seconds $PollTimeInSeconds
                
                # Work here to invoke send commands
                # Since we want the files to get generated under a subfolder, we replace the path to include the subfolder
                $sendCmd =  $sendCmd -ireplace [regex]::Escape($CommandsDir), "$SendDir/Sender"
                LogWrite "Invoking Cmd - Machine: $sendComputerName Command: $sendCmd" 
                $sendJob = Invoke-Command -Session $sendPSSession -ScriptBlock ([Scriptblock]::Create($sendCmd)) -AsJob 
                # non blocking loop to check if the process made a clean exit

                 # Calculate actual timeout value.
                # For tools such as ntttcp, we may need to add additional #s for runtime, wu and cd times 
                [int] $timeout = GetActualTimeOutValue -AdditionalTimeout $TimeoutValueBetweenCommandPairs -Line $sendCmd
                LogWrite "Waiting for $timeout seconds ..."
                # Updating progress for user
                Write-Host "Invoking $commandCount/$commandTotal commands for $Toolname and waiting for $timeout seconds..."
                $sw.Reset()
                $sw.Start()
                # check job status until job is done running
                while (([math]::Round($sw.Elapsed.TotalSeconds,0)) -lt $timeout) {
                    start-sleep -seconds $PollTimeInSeconds
                    if (($Toolname -eq "lagscope") -or ($Toolname -eq "secnetperf")) {
                        if ($sendJob.State -eq "Completed") {         
                            LogWrite "$Toolname exited on both Src machines after $([math]::Round($sw.Elapsed.TotalSeconds,0)) seconds"
                            break
                        }
                    } else {
                        if ($recvJob.State -eq "Completed" -and $sendJob.State -eq "Completed") {         
                            LogWrite "$Toolname exited on both Src and Dest machines after $([math]::Round($sw.Elapsed.TotalSeconds,0)) seconds"
                            break
                        }
                    }
                }
                # recv file takes longer to generate
                # if ($Toolname -eq "ntttcp") {
                #     Start-Sleep -seconds 900
                # }
                # check if job was completed
                if ($recvJob.State -ne "Completed") {
                    LogWrite " ++ $Toolname on Receiver did not exit cleanly with state " $recvJob.State
                } 
                if ($sendJob.State -ne "Completed") {
                    LogWrite " ++ $Toolname on Sender did not exit cleanly with state " $sendJob.State
                } 
                $sw.Stop() 
                # Since time is up, stop job process so that new commands can be issued
                Stop-Job $recvJob
                Stop-Job $sendJob
    
                # Clean up completed or failed job list
                Remove-Job $recvJob 
                Remove-Job $sendJob
    
                # Add sleep between before running the next command pair
                start-sleep -seconds $PollTimeInSeconds
    
            }
    
            $recvCommands.close()
            $sendCommands.close()
    
            LogWrite "Test runs completed. Collecting results..."

            # remove tool binaries because no need to copy
            Invoke-Command -Session $recvPSSession -ScriptBlock $ScriptBlockRemoveBinaries -ArgumentList "$RecvDir/Receiver/$Toolname/$Toolname" 
            Invoke-Command -Session $sendPSSession -ScriptBlock $ScriptBlockRemoveBinaries -ArgumentList "$SendDir/Sender/$Toolname/$Toolname"
    
            if ($BZip -eq $true) {
                #Zip the files on remote machines
                LogWrite "Zipping up results..."
                Invoke-Command -Session $recvPSSession -ScriptBlock $ScriptBlockCreateZip -ArgumentList ("$RecvDir/Receiver/$Toolname", "$RecvDir/Recv.zip")
                Invoke-Command -Session $sendPSSession -ScriptBlock $ScriptBlockCreateZip -ArgumentList ("$SendDir/Sender/$Toolname", "$SendDir/Send.zip")
     
                Remove-Item -Force -Path ("{0}/{1}_Receiver.zip" -f $CommandsDir, $Toolname) -Recurse -ErrorAction SilentlyContinue
                Remove-Item -Force -Path ("{0}/{1}_Sender.zip" -f $CommandsDir, $Toolname) -Recurse -ErrorAction SilentlyContinue
    
                #copy the zip files from remote machines to the current (orchestrator) machines
                Copy-Item -Path "$RecvDir/Recv.zip" -Destination ("{0}/{1}_Receiver.zip" -f $RecvDir, $Toolname) -FromSession $recvPSSession -Force
                Copy-Item -Path "$SendDir/Send.zip" -Destination ("{0}/{1}_Sender.zip" -f $SendDir, $Toolname) -FromSession $sendPSSession -Force
    
                Invoke-Command -Session $recvPSSession -ScriptBlock $ScriptBlockRemoveFileFolder -ArgumentList "$RecvDir/Recv.zip"
                Invoke-Command -Session $sendPSSession -ScriptBlock $ScriptBlockRemoveFileFolder -ArgumentList "$SendDir/Send.zip"
            } else {
                LogWrite "Copying directories..."
                Remove-Item -Force -Path ("{0}/{1}_Receiver" -f $CommandsDir, $Toolname) -Recurse -ErrorAction SilentlyContinue
                Remove-Item -Force -Path ("{0}/{1}_Sender" -f $CommandsDir, $Toolname) -Recurse -ErrorAction SilentlyContinue
    
                #copy just the entire results folder from remote machines to the current (orchestrator) machine
                Copy-Item -Path "$RecvDir/Receiver/$Toolname/" -Recurse -Destination ("{0}/{1}_Receiver" -f $CommandsDir, $Toolname) -FromSession $recvPSSession -Force
                Copy-Item -Path "$SendDir/Sender/$Toolname/" -Recurse -Destination ("{0}/{1}_Sender" -f $CommandsDir, $Toolname) -FromSession $sendPSSession -Force
            }
    
            if ($Bcleanup -eq $True) { 
                LogWrite "Cleaning up folders on Machine: $recvComputerName"
    
                #clean up the folders and files we created
                if($recvFolderExists -eq $false) {
                     # The folder never existed in the first place. we need to clean up the directories we created
                     Invoke-Command -Session $recvPSSession -ScriptBlock $ScriptBlockRemoveFolderTree -ArgumentList "$RecvDir"
                } else {
                    # this folder existed earlier on the machine. Leave the directory alone
                    # Remove just the child directories and the files we created. 
                    Invoke-Command -Session $recvPSSession -ScriptBlock $ScriptBlockRemoveFileFolder -ArgumentList "$RecvDir/Receiver"
                }
    
                LogWrite "Cleaning up folders on Machine: $sendComputerName"
    
                if($sendFolderExists -eq $false) {
                     Invoke-Command -Session $sendPSSession -ScriptBlock $ScriptBlockRemoveFolderTree -ArgumentList "$SendDir"
                } else {
                    # this folder existed earlier on the machine. Leave the directory alone
                    # Remove just the child directories and the files we created. Leave the directory alone
                    Invoke-Command -Session $sendPSSession -ScriptBlock $ScriptBlockRemoveFileFolder -ArgumentList "$SendDir/Sender"
                }
            } # if ($Bcleanup -eq $true)
            $gracefulCleanup = $True
        } # end try
        catch {
           LogWrite "Exception $($_.Exception.Message) in $($MyInvocation.MyCommand.Name)"
        }
        finally {
            if($gracefulCleanup -eq $False)
            {
                if ($null -ne $recvCommands ) {$recvCommands.close()}
                if ($null -ne $sendCommands) {$sendCommands.close()}

                Stop-Job *
                Remove-Job *
                
                Invoke-Command -Session $recvPSSession -ScriptBlock $ScriptBlockTaskKill -ArgumentList $Toolname
                Invoke-Command -Session $sendPSSession -ScriptBlock $ScriptBlockTaskKill -ArgumentList $Toolname
            
            }
    
            LogWrite "Cleaning up the firewall rules that were created as part of script run..."
            # Clean up the firewall rules that this script created
            Invoke-Command -Session $recvPSSession -ScriptBlock $ScriptBlockCleanupFirewallRules -ArgumentList ("50000:50512/tcp", $RecvComputerCreds)
            Invoke-Command -Session $sendPSSession -ScriptBlock $ScriptBlockCleanupFirewallRules -ArgumentList ("50000:50512/tcp", $SendComputerCreds)
            Invoke-Command -Session $recvPSSession -ScriptBlock $ScriptBlockCleanupFirewallRules -ArgumentList ("50000:50512/udp", $RecvComputerCreds)
            Invoke-Command -Session $sendPSSession -ScriptBlock $ScriptBlockCleanupFirewallRules -ArgumentList ("50000:50512/udp", $SendComputerCreds)
            
            LogWrite "Cleaning up public private key and known hosts that were created as part of script run"
            if ($PassAuth) {
                # Delete authorized host from receiver and sender computer
                Invoke-Command -Session $recvPSSession -ScriptBlock $ScriptBlockRemoveAuthorizedHost 
                Invoke-Command -Session $sendPSSession -ScriptBlock $ScriptBlockRemoveAuthorizedHost 

                # delete public and private key
                Remove-Item -Path $keyFilePath -ErrorAction SilentlyContinue -Force
                Remove-Item -Path $pubKeyFilePath -ErrorAction SilentlyContinue -Force
                Remove-Item -Path $sshCommandFilePath -ErrorAction SilentlyContinue -Force
            }

            # remove receiver and sender computer as known hosts
            head -n -6 "$homePath/.ssh/known_hosts" | Out-Null

            LogWrite "Cleaning up Remote PS Sessions"
            # Clean up the PS Sessions
            Remove-PSSession $sendPSSession  -ErrorAction Ignore
            Remove-PSSession $recvPSSession  -ErrorAction Ignore
    
        } #finally
    } # ProcessToolCommands()