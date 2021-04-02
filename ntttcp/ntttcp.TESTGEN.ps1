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
        [parameter(Mandatory=$true)]   [Int]    $BufferLen
    )

    [string] $out = (Join-Path -Path $RecvDir -ChildPath "$Fname")
    [string] $cmd = "./ntttcp -r -m  `"$Conn,*,$g_DestIp`" $Proto -V -b $BufferLen -W $($g_Config.Warmup) -C $($g_Config.Cooldown) -p $Port -t $($g_Config.Time) $($g_Config.RecvOptions) -x $out.xml > $out.txt"
    [string] $cmdOut = (Join-Path -Path $OutDir -ChildPath "$Fname")
    Write-Output $cmd | Out-File -Encoding ascii -Append "$cmdOut.txt"
    Write-Output $cmd | Out-File -Encoding ascii -Append $g_log
    Write-Output $cmd | Out-File -Encoding ascii -Append $g_logRecv
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
        [parameter(Mandatory=$true)]   [Int]    $BufferLen    
    )

    [string] $out = (Join-Path -Path $SendDir -ChildPath "$Fname")
    [string] $cmd = "./ntttcp -s -m `"$Conn,*,$g_DestIp`" $Proto -V -b $BufferLen -W $($g_Config.Warmup) -C $($g_Config.Cooldown) -p $Port -t $($g_Config.Time) $($g_Config.SendOptions) -x $out.xml > $out.txt"
    [string] $cmdOut = (Join-Path -Path $OutDir -ChildPath "$Fname")
    Write-Output $cmd | Out-File -Encoding ascii -Append "$cmdOut.txt"
    Write-Output $cmd | Out-File -Encoding ascii -Append $g_log
    Write-Output $cmd | Out-File -Encoding ascii -Append $g_logSend    
    Write-Host   $cmd 
} # test_send()

function test_protocol {
    [CmdletBinding()]
    Param(
        [parameter(Mandatory=$true)] [String] $OutDir,
        [parameter(Mandatory=$true)]  [string] $SendDir,
        [parameter(Mandatory=$true)]  [string] $RecvDir, 
        [parameter(Mandatory=$true)] [String] $Proto
    )
    banner -Msg "$Proto Tests"
    $ProtoOutDir = (Join-Path -Path $OutDir -ChildPath "$Proto") 
    $ProtoSendDir = (Join-Path -Path $SendDir -ChildPath "$Proto") 
    $ProtoRecvDir = (Join-Path -Path $RecvDir -ChildPath "$Proto") 
    New-Item -ItemType directory -Path $ProtoOutDir | Out-Null
    $protoParam = if ($Proto -eq "udp") {"-u"} else {""};
    foreach ($BufferLen in $g_Config.($Proto).BufferLen)
    {
        foreach ($Conn in $g_Config.($Proto).Connections)
        {
            for ($i=0; $i -lt $g_Config.Iterations; $i++) 
            {
                test_recv -Conn $Conn -Port ($g_Config.StartPort+$i) -Proto $protoParam -OutDir $ProtoOutDir -Fname "$Proto.recv.m$Conn.l$BufferLen.iter$i" -RecvDir $ProtoRecvDir -BufferLen $BufferLen 
                test_send -Conn $Conn -Port ($g_Config.StartPort+$i) -Proto $protoParam -OutDir $ProtoOutDir -Fname "$Proto.send.m$Conn.l$BufferLen.iter$i" -SendDir $ProtoSendDir -BufferLen $BufferLen
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
        [parameter(Mandatory=$true)]  [string] $SendDir,
        [parameter(Mandatory=$true)]  [string] $RecvDir
    )
    if ($null -ne $g_Config.tcp)
    {
        test_protocol -OutDir $OutDir -SendDir $SendDir -RecvDir $RecvDir -Proto "tcp" 
    }

    if ($null -ne $g_Config.udp)
    {
        test_protocol -OutDir $OutDir -SendDir $SendDir -RecvDir $RecvDir -Proto "udp" 
    }

} # test_ntttcp()

#===============================================
# External Functions - Main Program
#===============================================
function test_main {
    Param(
        [parameter(Mandatory=$true)]  [string] $DestIp,
        [parameter(Mandatory=$true)]  [string] $SrcIp,
        [parameter(Mandatory=$true)]  [ValidateScript({Test-Path $_ -PathType Container})] [String] $OutDir,
        [parameter(Mandatory=$false)] [ValidateSet('Azure','Default', 'Detail')] [string] $ConfigName = "Default",
        [parameter(Mandatory=$true)]  [string] $DestDir,
        [parameter(Mandatory=$true)]  [string] $SrcDir
    )
    input_display
    $allConfig = Get-Content ./ntttcp/ntttcp.Config.json | ConvertFrom-Json
    $g_Config = $allConfig.("Ntttcp$ConfigName")
    [string] $g_DestIp     = $DestIp.Trim()
    [string] $g_SrcIp      = $SrcIp.Trim()
    [string] $dir          = (Join-Path -Path $OutDir -ChildPath "ntttcp") 
    [string] $g_log        = "$dir/NTTTCP.Commands.txt"
    [string] $g_logSend    = "$dir/NTTTCP.Commands.Send.txt"
    [string] $g_logRecv    = "$dir/NTTTCP.Commands.Recv.txt"
    [string] $sendDir   = (Join-Path -Path $SrcDir -ChildPath "ntttcp")
    [string] $recvDir   = (Join-Path -Path $DestDir -ChildPath "ntttcp")

    # Edit spaces in path for Invoke-Expression compatibility
    $dir = $dir -replace ' ','` '
    
    New-Item -ItemType directory -Path $dir | Out-Null
    Write-Host "test_ntttcp -OutDir $dir -ConfigName $g_ConfigName"

    test_ntttcp -OutDir $dir -Config $g_Config -SendDir $sendDir -RecvDir $recvDir
} test_main @PSBoundParameters # Entry Point