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
    [string] $cmd = "./lagscope -r -p$Port $($global:Config.Options)"
    Write-Output $cmd | Out-File -Encoding ascii -Append $global:log
    Write-Output $cmd | Out-File -Encoding ascii -Append $global:logRecv
    Write-Host   $cmd 
} # test_recv()

function test_send {
    [CmdletBinding()]
    Param(
        [parameter(Mandatory=$false)]  [string] $Oper,
        [parameter(Mandatory=$true)]   [int]    $Port,
        [parameter(Mandatory=$false)]  [String] $Options,
        [parameter(Mandatory=$true)]   [String] $OutDir,
        [parameter(Mandatory=$true)]   [String] $Fname,
        [parameter(Mandatory=$false)]  [bool]   $NoDumpParam = $false,
        [parameter(Mandatory=$true)]   [String] $SendDir

    )
    [int] $rangeus  = 10
    [int] $rangemax = 98

    [string] $out        = (Join-Path -Path $SendDir -ChildPath "$Fname")
    [string] $cmd = "./lagscope $Oper -s`"$g_DestIp`" -p$Port -V $($global:Config.Options) -H -c$rangemax -l$rangeus -P`"$out.per.json`" -R`"$out.data.csv`" > `"$out.txt`""
    Write-Output $cmd | Out-File -Encoding ascii -Append $global:log
    Write-Output $cmd | Out-File -Encoding ascii -Append $global:logSend
    Write-Host   $cmd 
} # test_send()

function test_lagscope_generate {
    [CmdletBinding()]
    Param(
        [parameter(Mandatory=$true)] [String] $OutDir,
        [parameter(Mandatory=$true)]  [string] $SendDir,
        [parameter(Mandatory=$true)]  [string] $RecvDir
    )

    # Iteration Tests capturing each transaction time
    # - Measures over input samples
    if ($global:Config.PingIterations -gt 0)
    {
        banner -Msg "Iteration Tests: [tcp] operations per bounded iterations"
        for ($i=0; $i -lt $global:Config.Iterations; $i++) 
        {
            [int] $portstart = $global:Config.StartPort + ($i * $global:Config.Iterations)
    
            test_send -Oper "-n$($global:Config.PingIterations)" -Port $portstart -OutDir $OutDir -Fname "tcp.i$($global:Config.PingIterations).iter$i" -SendDir $SendDir
            test_recv -Port $portstart -RecvDir $RecvDir
        }
    }
    # Transactions per 10s
    # - Measures operations per bounded time.
    if ($global:Config.Time -gt 0)
    {
        banner -Msg "Time Tests: [tcp] operations per bounded time"
        for ($i=0; $i -lt $global:Config.Iterations; $i++) 
        {
            [int] $portstart = $global:Config.StartPort + ($i * $global:Config.Iterations)
            
            test_send -Oper "-t$($global:Config.Time)" -Port $portstart -OutDir $OutDir -Fname "tcp.t$($global:Config.Time).iter$i" -SendDir $SendDir
            test_recv -Port $portstart -RecvDir $RecvDir
        }
    }
} # test_lagscope_generate()

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
    $allConfig = Get-Content ./lagscope/lagscope.Config.json | ConvertFrom-Json
    [Object] $global:Config = $allConfig.("Lagscope$ConfigName")
    [string] $global:DestIp  = $DestIp.Trim()
    [string] $global:SrcIp   = $SrcIp.Trim()
    [string] $dir       = (Join-Path -Path $OutDir -ChildPath "lagscope")  
    [string] $global:log     = "$dir/LAGSCOPE.Commands.txt"
    [string] $global:logSend = "$dir/LAGSCOPE.Commands.Send.txt"
    [string] $global:logRecv = "$dir/LAGSCOPE.Commands.Recv.txt" 
    [string] $sendDir   = (Join-Path -Path $SrcDir -ChildPath "lagscope")
    [string] $recvDir   = (Join-Path -Path $DestDir -ChildPath "lagscope")

    New-Item -ItemType directory -Path $dir | Out-Null

    test_lagscope_generate -OutDir $dir -SendDir $sendDir -RecvDir $recvDir
} test_main @PSBoundParameters # Entry Point