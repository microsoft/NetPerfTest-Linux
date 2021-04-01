#===============================================
# Script Input Parameters Enforcement
#===============================================
Param(
    [parameter(Mandatory=$true)]  [string] $DestIp,
    [parameter(Mandatory=$true)]  [string] $SrcIp,
    [parameter(Mandatory=$true)]  [ValidateScript({Test-Path $_ -PathType Container})] [String] $OutDir = "",
    [parameter(Mandatory=$false)] [ValidateSet('Azure','Default', 'Detail')] [string] $ConfigName = "Default",
    [parameter(Mandatory=$true)]  [string] $DestDir,
    [parameter(Mandatory=$true)]  [string] $SrcDir
)
$scriptName = $MyInvocation.MyCommand.Name 

function input_display {
    $g_path = Get-Location

    Write-Host "============================================"
    Write-Host "$g_path\$scriptName"
    Write-Host " Inputs:"
    Write-Host "  -Config     = $ConfigName"
    Write-Host "  -DestIp     = $DestIp"
    Write-Host "  -SrcIp      = $SrcIp"
    Write-Host "  -OutDir     = $OutDir"
    Write-Host "============================================"
} # input_display()

#===============================================
# Internal Functions
#===============================================
function test_recv {
    [CmdletBinding()]
    Param(
        [parameter(Mandatory=$true)]   [Int]    $Conn,
        [parameter(Mandatory=$true)]   [Int]    $Port,
        [parameter(Mandatory=$false)]  [string] $Proto,
        [parameter(Mandatory=$true)]   [String] $OutDir,
        [parameter(Mandatory=$true)]   [String] $Fname,
        [parameter(Mandatory=$true)]  [string] $RecvDir, 
        [parameter(Mandatory=$true)]   [Int]    $BufferLen,
        [parameter(Mandatory=$true)] [Object] $Config 
    )

    [string] $out = (Join-Path -Path $RecvDir -ChildPath "$Fname")
    [string] $cmd = "./ntttcp -r -m  `"$Conn,*,$global:DestIp`" $Proto -V -b $BufferLen -W $($Config.Warmup) -C $($Config.Cooldown) -p $Port -t $($Config.Time) $($Config.RecvOptions) -x $out.xml > $out.txt"
    [string] $cmdOut = (Join-Path -Path $OutDir -ChildPath "$Fname")
    Write-Output $cmd | Out-File -Encoding ascii -Append "$cmdOut.txt"
    Write-Output $cmd | Out-File -Encoding ascii -Append $global:log
    Write-Output $cmd | Out-File -Encoding ascii -Append $global:logRecv
    Write-Host   $cmd 

} # test_recv()

function test_send {
    [CmdletBinding()]
    Param(
        [parameter(Mandatory=$true)]   [Int]    $Conn,
        [parameter(Mandatory=$true)]   [Int]    $Port,
        [parameter(Mandatory=$false)]  [string] $Proto,
        [parameter(Mandatory=$true)]   [String] $OutDir,
        [parameter(Mandatory=$true)]   [String] $Fname,
        [parameter(Mandatory=$true)]  [string] $SendDir, 
        [parameter(Mandatory=$true)]   [Int]    $BufferLen,
        [parameter(Mandatory=$true)] [Object] $Config        
    )

    [string] $out = (Join-Path -Path $SendDir -ChildPath "$Fname")
    [string] $cmd = "./ntttcp -s -m `"$Conn,*,$global:DestIp`" $Proto -V -b $BufferLen -W $($Config.Warmup) -C $($Config.Cooldown) -p $Port -t $($Config.Time) $($Config.SendOptions) -x $out.xml > $out.txt"
    [string] $cmdOut = (Join-Path -Path $OutDir -ChildPath "$Fname")
    Write-Output $cmd | Out-File -Encoding ascii -Append "$cmdOut.txt"
    Write-Output $cmd | Out-File -Encoding ascii -Append $global:log
    Write-Output $cmd | Out-File -Encoding ascii -Append $global:logSend    
    Write-Host   $cmd 
} # test_send()

function test_protocol {
    [CmdletBinding()]
    Param(
        [parameter(Mandatory=$true)] [String] $OutDir,
        [parameter(Mandatory=$true)] [Object[]] $ConnList,
        [parameter(Mandatory=$true)]  [string] $SendDir,
        [parameter(Mandatory=$true)]  [string] $RecvDir, 
        [parameter(Mandatory=$true)]  [Object[]] $BufferLenList,
        [parameter(Mandatory=$true)] [Object] $Config,
        [parameter(Mandatory=$true)] [String] $Proto
    )
    $protoParam = if ($Proto -eq "udp") {"-u"} else {""};
    foreach ($BufferLen in $BufferLenList)
    {
        foreach ($Conn in $ConnList)
        {
            for ($i=0; $i -lt $Config.Iterations; $i++) 
            {
                test_recv -Conn $Conn -Port ($Config.StartPort+$i) -Proto $protoParam -OutDir $OutDir -Fname "$Proto.recv.m$Conn.iter$i" -RecvDir $RecvDir -BufferLen $BufferLen
                test_send -Conn $Conn -Port ($Config.StartPort+$i) -Proto $protoParam -OutDir $OutDir -Fname "$Proto.send.m$Conn.iter$i" -SendDir $SendDir -BufferLen $BufferLen
            }        
        }
    }
    Write-Host " "
} # test_tcp()

function banner {
    [CmdletBinding()]
    Param(
        [parameter(Mandatory=$true)] [String] $Msg
    )

    Write-Host "==========================================================================="
    Write-Host "| $Msg"
    Write-Host "==========================================================================="
} # banner()

function test_ntttcp {
    [CmdletBinding()]
    Param(
        [parameter(Mandatory=$true)] [String] $OutDir,
        [parameter(Mandatory=$true)] [Object] $Config,
        [parameter(Mandatory=$true)]  [string] $SendDir,
        [parameter(Mandatory=$true)]  [string] $RecvDir
    )
    if ($Config.Tcp)
    {
        banner -Msg "TCP Tests"
        $tcpDir = (Join-Path -Path $OutDir -ChildPath "tcp") 
        $tcpDirSend = (Join-Path -Path $SendDir -ChildPath "tcp") 
        $tcpDirRecv = (Join-Path -Path $RecvDir -ChildPath "tcp")
        test_protocol -OutDir $tcpDir -SendDir $tcpDirSend -RecvDir $tcpDirRecv -ConnList $Config.ConnectionsTcp -BufferLenList $Config.BufferLenTcp -Config $Config -Proto "tcp" 
    }

    if ($Config.Udp)
    {
        banner -Msg "UDP Tests"
        $udpDir = (Join-Path -Path $OutDir -ChildPath "udp") 
        $udpDirSend = (Join-Path -Path $SendDir -ChildPath "udp") 
        $udpDirRecv = (Join-Path -Path $RecvDir -ChildPath "udp") 
        test_protocol -OutDir $udpDir -SendDir $udpDirSend -RecvDir $udpDirRecv -ConnList $Config.ConnectionsUdp -BufferLenList $Config.BufferLenUdp -Config $Config -Proto "udp" 
    }

} # test_ntttcp()

#===============================================
# External Functions - Main Program
#===============================================
function test_main {
    Param(
        [parameter(Mandatory=$true)]  [string] $DestIp,
        [parameter(Mandatory=$true)]  [string] $SrcIp,
        [parameter(Mandatory=$true)]  [ValidateScript({Test-Path $_ -PathType Container})] [String] $OutDir = "",
        [parameter(Mandatory=$false)] [ValidateSet('Azure','Default', 'Detail')] [string] $ConfigName = "Default",
        [parameter(Mandatory=$true)]  [string] $DestDir,
        [parameter(Mandatory=$true)]  [string] $SrcDir
    )
    input_display
    $allConfig = Get-Content ./ntttcp/ntttcp.Config.json | ConvertFrom-Json
    $Config = $allConfig.("Ntttcp$ConfigName")
    [string] $global:DestIp     = $DestIp.Trim()
    [string] $global:SrcIp      = $SrcIp.Trim()
    [string] $dir          = (Join-Path -Path $OutDir -ChildPath "ntttcp") 
    [string] $global:log        = "$dir/NTTTCP.Commands.txt"
    [string] $global:logSend    = "$dir/NTTTCP.Commands.Send.txt"
    [string] $global:logRecv    = "$dir/NTTTCP.Commands.Recv.txt"
    [string] $sendDir   = (Join-Path -Path $SrcDir -ChildPath "ntttcp")
    [string] $recvDir   = (Join-Path -Path $DestDir -ChildPath "ntttcp")

    # Edit spaces in path for Invoke-Expression compatibility
    $dir = $dir -replace ' ','` '
    
    New-Item -ItemType directory -Path $dir | Out-Null
    Write-Host "test_ntttcp -OutDir $dir -ConfigFile $g_ConfigFile"

    test_ntttcp -OutDir $dir -ConfigFile $g_ConfigFile -SendDir $sendDir -RecvDir $recvDir
} test_main @PSBoundParameters # Entry Point