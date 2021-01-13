#===============================================
# Script Input Parameters Enforcement
#===============================================
Param(
    [parameter(Mandatory=$false)] [switch] $Detail = $false,
    [parameter(Mandatory=$false)] [Int]    $Iterations = 1,
    [parameter(Mandatory=$false)] [ValidateSet('Sampling','Testing')] [string] $Config = "Sampling",
    [parameter(Mandatory=$true)]  [string] $DestIp,
    [parameter(Mandatory=$true)]  [string] $SrcIp,
    [parameter(Mandatory=$true)]  [ValidateScript({Test-Path $_ -PathType Container})] [String] $OutDir = "",
    [parameter(Mandatory=$true)]  [string] $DestDir,
    [parameter(Mandatory=$true)]  [string] $SrcDir
)
$scriptName = $MyInvocation.MyCommand.Name 

function input_display {
    $g_path = Get-Location

    Write-Host "============================================"
    Write-Host "$g_path\$scriptName"
    Write-Host " Inputs:"
    Write-Host "  -Detail     = $Detail"
    Write-Host "  -Iterations = $Iterations"
    Write-Host "  -Config     = $Config"
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
        [parameter(Mandatory=$true)]  [string] $RecvDir
    )

    [string] $out = (Join-Path -Path $RecvDir -ChildPath "$Fname")
    [string] $cmd = "./ntttcp -r -e -m  `"$Conn,*,$g_DestIp`" $proto -V -b 65536 -W $g_ptime -C $g_ptime -p $Port -t $g_runtime -N -x $out.xml > $out.txt"
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
        [parameter(Mandatory=$true)]  [string] $SendDir

    )

    [string] $out = (Join-Path -Path $SendDir -ChildPath "$Fname")
    [string] $cmd = "./ntttcp -s -m `"$Conn,*,$g_DestIp`" $proto -V -b 65536 -W $g_ptime -C $g_ptime -p $Port -t $g_runtime -N -x $out.xml > $out.txt"
    [string] $cmdOut = (Join-Path -Path $OutDir -ChildPath "$Fname")
    Write-Output $cmd | Out-File -Encoding ascii -Append "$cmdOut.txt"
    Write-Output $cmd | Out-File -Encoding ascii -Append $g_log
    Write-Output $cmd | Out-File -Encoding ascii -Append $g_logSend    
    Write-Host   $cmd 
} # test_send()

function test_udp {
    [CmdletBinding()]
    Param(
        [parameter(Mandatory=$true)] [String] $OutDir,
        [parameter(Mandatory=$true)] [Int]    $Conn,
        [parameter(Mandatory=$true)]  [string] $SendDir,
        [parameter(Mandatory=$true)]  [string] $RecvDir
    )
    
    [int]    $tmp    = 50100
    [string] $udpstr = "-u"
    for ($i=0; $i -lt $g_iters; $i++) {
        test_recv -Conn $Conn -Port ($tmp+$i) -Proto $udpstr -OutDir $OutDir -Fname "udp.recv.m$Conn.iter$i" -RecvDir $RecvDir
        test_send -Conn $Conn -Port ($tmp+$i) -Proto $udpstr -OutDir $OutDir -Fname "udp.send.m$Conn.iter$i" -SendDir $SendDir
    }
} # test_udp()

function test_tcp {
    [CmdletBinding()]
    Param(
        [parameter(Mandatory=$true)] [String] $OutDir,
        [parameter(Mandatory=$true)] [Int]    $Conn,
        [parameter(Mandatory=$true)]  [string] $SendDir,
        [parameter(Mandatory=$true)]  [string] $RecvDir
    )

    [string] $tcpstr = ""
    [int]    $tmp    = 50100
    for ($i=0; $i -lt $g_iters; $i++) {
        test_recv -Conn $Conn -Port ($tmp+$i) -Proto $tcpstr -OutDir $OutDir -Fname "tcp.recv.m$Conn.iter$i" -RecvDir $RecvDir
        test_send -Conn $Conn -Port ($tmp+$i) -Proto $tcpstr -OutDir $OutDir -Fname "tcp.send.m$Conn.iter$i" -SendDir $SendDir
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
        [parameter(Mandatory=$false)] [ValidateScript({Test-Path $_})] [String] $ConfigFile,
        [parameter(Mandatory=$true)]  [string] $SendDir,
        [parameter(Mandatory=$true)]  [string] $RecvDir
    )

    #Load the variables needed to generate the commands
    # execution time in seconds
    [int] $g_runtime = 60
    [int] $g_ptime   = 2

    # execution time ($g_runtime) in seconds, wu, cd times ($g_ptime) will come from the Config ps1 file, if specified and take precedence over defaults 
    if ($ConfigFile -ne $null) {
        Try
        {
            . .\$ConfigFile
        }
        Catch
        {
            Write-Host "$ConfigFile will not be used. Exception $($_.Exception.Message) in $($MyInvocation.MyCommand.Name)"
        }
    }

    # NTTTCP ^2 connection scaling to MAX supported.
    [int]   $ConnMax  = 512 # NTTTCP maximum connections is 999.
    [int[]] $ConnList = @(64)
    if ($g_detail) {
        $ConnList = @(1, 2, 4, 8, 16, 32, 64, 128, 256, $ConnMax)
    }

    [string] $dir = $OutDir
    # Separate loops simply for output readability
    banner -Msg "TCP Tests"
    $dir = (Join-Path -Path $OutDir -ChildPath "tcp") 
    $dirSend = (Join-Path -Path $SendDir -ChildPath "tcp") 
    $dirRecv = (Join-Path -Path $RecvDir -ChildPath "tcp") 
    New-Item -ItemType directory -Path $dir | Out-Null
    foreach ($Conn in $ConnList) {
        test_tcp -Conn $Conn -OutDir $dir -SendDir $dirSend -RecvDir $dirRecv
        Write-Host " "
    }

    banner -Msg "UDP Tests"
    $dir = (Join-Path -Path $OutDir -ChildPath "udp") 
    $dirSend = (Join-Path -Path $SendDir -ChildPath "udp") 
    $dirRecv = (Join-Path -Path $RecvDir -ChildPath "udp") 
    New-Item -ItemType directory -Path $dir | Out-Null
    foreach ($Conn in $ConnList) {
        test_udp -Conn $Conn -OutDir $dir -SendDir $dirSend -RecvDir $dirRecv
        Write-Host " "
    }
} # test_ntttcp()

#===============================================
# External Functions - Main Program
#===============================================
function test_main {
    Param(
        [parameter(Mandatory=$false)] [switch] $Detail = $false,
        [parameter(Mandatory=$false)] [Int]    $Iterations = 1,
        [parameter(Mandatory=$false)] [ValidateSet('Sampling','Testing')] [string] $Config = "Sampling",
        [parameter(Mandatory=$true)]  [string] $DestIp,
        [parameter(Mandatory=$true)]  [string] $SrcIp,
        [parameter(Mandatory=$true)]  [String] $OutDir = "" ,
        [parameter(Mandatory=$true)]  [string] $DestDir,
        [parameter(Mandatory=$true)]  [string] $SrcDir
    )
    input_display

    [int]    $g_iters      = $Iterations
    [bool]   $g_detail     = $Detail
    [string] $g_DestIp     = $DestIp.Trim()
    [string] $g_SrcIp      = $SrcIp.Trim()
    [string] $dir          = (Join-Path -Path $OutDir -ChildPath "ntttcp") 
    [string] $g_log        = "$dir/NTTTCP.Commands.txt"
    [string] $g_logSend    = "$dir/NTTTCP.Commands.Send.txt"
    [string] $g_logRecv    = "$dir/NTTTCP.Commands.Recv.txt"
    [string] $g_ConfigFile = "./ntttcp/NTTTCP.$Config.Config.ps1"
    [string] $sendDir   = (Join-Path -Path $SrcDir -ChildPath "ntttcp")
    [string] $recvDir   = (Join-Path -Path $DestDir -ChildPath "ntttcp")

    # Edit spaces in path for Invoke-Expression compatibility
    $dir = $dir -replace ' ','` '
    
    New-Item -ItemType directory -Path $dir | Out-Null
    Write-Host "test_ntttcp -OutDir $dir -ConfigFile $g_ConfigFile"

    # Use default values if config file does not exist
    if (Test-Path $g_ConfigFile) {
        test_ntttcp -OutDir $dir -ConfigFile $g_ConfigFile -SendDir $sendDir -RecvDir $recvDir
    } else {
        test_ntttcp -OutDir $dir -SendDir $sendDir -RecvDir $recvDir
    }
} test_main @PSBoundParameters # Entry Point