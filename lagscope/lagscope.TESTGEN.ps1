Param(
    [parameter(Mandatory=$false)] [Int]    $Iterations = 1,
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
 
    Write-Host "  -Iterations = $Iterations"
    Write-Host "  -DestIp     = $DestIp"
    Write-Host "  -SrcIp      = $SrcIp"
    Write-Host "  -OutDir     = $OutDir"
    Write-Host "============================================"
} # input_display()

#===============================================
# Internal Functions
#===============================================
function banner {
    [CmdletBinding()]
    Param(
        [parameter(Mandatory=$true)] [String] $Msg
    )

    Write-Host "==========================================================================="
    Write-Host "| $Msg"
    Write-Host "==========================================================================="
} # banner()

function test_recv {
    [CmdletBinding()]
    Param(
        [parameter(Mandatory=$true)]   [int]    $Port,
        [parameter(Mandatory=$true)]   [String] $RecvDir
    )
    [string] $cmd = "./lagscope -r -p$Port"
    Write-Output $cmd | Out-File -Encoding ascii -Append $g_log
    Write-Output $cmd | Out-File -Encoding ascii -Append $g_logRecv
    Write-Host   $cmd 
} # test_recv()

function test_send {
    [CmdletBinding()]
    Param(
        [parameter(Mandatory=$false)]  [string] $Iter,
        [parameter(Mandatory=$false)]  [int]    $Secs,
        [parameter(Mandatory=$true)]   [int]    $Port,
        [parameter(Mandatory=$false)]  [String] $Options,
        [parameter(Mandatory=$true)]   [String] $OutDir,
        [parameter(Mandatory=$true)]   [String] $Fname,
        [parameter(Mandatory=$false)]  [bool]   $NoDumpParam = $false,
        [parameter(Mandatory=$true)]   [String] $SendDir

    )

    #[int] $msgbytes = 4  #lagscope default is 4B, no immediate need to specify.
    [int] $rangeus  = 10
    [int] $rangemax = 98

    [string] $out        = (Join-Path -Path $SendDir -ChildPath "$Fname")
    [string] $cmd = "./lagscope $Iter -s`"$g_DestIp`" -p$Port -V -H -c$rangemax -l$rangeus -P`"$out.per.json`" -R`"$out.data.csv`" > `"$out.txt`""
    Write-Output $cmd | Out-File -Encoding ascii -Append $g_log
    Write-Output $cmd | Out-File -Encoding ascii -Append $g_logSend
    Write-Host   $cmd 
} # test_send()

function test_lagscope_generate {
    [CmdletBinding()]
    Param(
        [parameter(Mandatory=$true)] [String] $OutDir,
        [parameter(Mandatory=$true)]  [string] $SendDir,
        [parameter(Mandatory=$true)]  [string] $RecvDir

    )

    # Normalize output directory
    $dir = $OutDir

    # Iteration Tests capturing each transaction time
    # - Measures over input samples
    banner -Msg "Iteration Tests: [tcp] operations per bounded iterations"
    [int] $tmp  = 50001
    [int] $iter = 10000 
    for ($i=0; $i -lt $g_iters; $i++) {
        [int] $portstart = $tmp + ($i * $g_iters)

        test_send -Iter "-n$iter" -Port $portstart -OutDir $dir -Fname "tcp.i$iter.iter$i" -SendDir $SendDir
        test_recv -Port $portstart -RecvDir $RecvDir
    }

    # Transactions per 10s
    # - Measures operations per bounded time.
    banner -Msg "Time Tests: [tcp] operations per bounded time"
    [int] $tmp = 50001
    [int] $sec = 10
    for ($i=0; $i -lt $g_iters; $i++) {
        [int] $portstart = $tmp + ($i * $g_iters)
        
        # Default
        test_send -Iter "-t$sec" -Port $portstart -Options "" -OutDir $dir -Fname "tcp.t$sec.iter$i" -SendDir $SendDir
        test_recv -Port $portstart -RecvDir $RecvDir
        
    }
} # test_lagscope_generate()

#===============================================
# External Functions - Main Program
#===============================================
function test_main {
    Param(
        [parameter(Mandatory=$false)] [Int]    $Iterations = 1,
        [parameter(Mandatory=$true)]  [string] $DestIp,
        [parameter(Mandatory=$true)]  [string] $SrcIp,
        [parameter(Mandatory=$true)]  [ValidateScript({Test-Path $_ -PathType Container})] [String] $OutDir = "",
        [parameter(Mandatory=$true)]  [string] $DestDir,
        [parameter(Mandatory=$true)]  [string] $SrcDir

    )
    input_display
    
    [int]    $g_iters   = $Iterations
    [string] $g_DestIp  = $DestIp.Trim()
    [string] $g_SrcIp   = $SrcIp.Trim()
    [string] $dir       = (Join-Path -Path $OutDir -ChildPath "lagscope")  
    [string] $g_log     = "$dir/LAGSCOPE.Commands.txt"
    [string] $g_logSend = "$dir/LAGSCOPE.Commands.Send.txt"
    [string] $g_logRecv = "$dir/LAGSCOPE.Commands.Recv.txt" 
    [string] $sendDir   = (Join-Path -Path $SrcDir -ChildPath "lagscope")
    [string] $recvDir   = (Join-Path -Path $DestDir -ChildPath "lagscope")

    New-Item -ItemType directory -Path $dir | Out-Null
    
    # Optional - Edit spaces in output path for Invoke-Expression compatibility
    # $dir  = $dir  -replace ' ','` '

    test_lagscope_generate -OutDir $dir -SendDir $sendDir -RecvDir $recvDir
} test_main @PSBoundParameters # Entry Point