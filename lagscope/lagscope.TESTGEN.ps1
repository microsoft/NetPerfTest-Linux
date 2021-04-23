Param(
    [parameter(Mandatory=$true)]  [string] $DestIp,
    [parameter(Mandatory=$true)]  [string] $SrcIp,
    [parameter(Mandatory=$true)]  [ValidateScript({Test-Path $_ -PathType Container})] [String] $OutDir = "",
    [parameter(Mandatory=$false)] [string] $Config = "Default",
    [parameter(Mandatory=$true)]  [string] $DestDir,
    [parameter(Mandatory=$true)]  [string] $SrcDir
)
$scriptName = $MyInvocation.MyCommand.Name 

function input_display {
    $g_path = Get-Location

    Write-Host "============================================"
    Write-Host "$g_path\$scriptName"
    Write-Host " Inputs:"
 
    Write-Host "  -Config     = $Config"
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
        [parameter(Mandatory=$true)]   [int]    $Port
    )
    [string] $cmd = "./lagscope -r -p$Port $($g_Config.Options)"
    Write-Output $cmd | Out-File -Encoding ascii -Append $g_log
    Write-Output $cmd | Out-File -Encoding ascii -Append $g_logRecv
    Write-Host   $cmd 
} # test_recv()

function test_send {
    [CmdletBinding()]
    Param(
        [parameter(Mandatory=$true)]  [string] $Oper,
        [parameter(Mandatory=$true)]   [int]    $Port,
        [parameter(Mandatory=$true)]   [String] $Fname,
        [parameter(Mandatory=$true)]   [String] $SendDir,
        [parameter(Mandatory=$true)]  [string] $OutDir
    )
    [int] $rangeus  = 10
    [int] $rangemax = 98

    [string] $out    = (Join-Path -Path $SendDir -ChildPath "$Fname")
    [string] $cmd    = "./lagscope $Oper -s`"$g_DestIp`" -p$Port -V $($g_Config.Options) -H -c$rangemax -l$rangeus -P`"$out.per.json`" -R`"$out.data.csv`" > `"$out.txt`""
    [string] $cmdOut = (Join-Path -Path $OutDir -ChildPath "$Fname")
    Write-Output $cmd | Out-File -Encoding ascii -Append "$cmdOut.txt"
    Write-Output $cmd | Out-File -Encoding ascii -Append $g_log
    Write-Output $cmd | Out-File -Encoding ascii -Append $g_logSend
    Write-Host   $cmd 
} # test_send()

function test_operations {
    [CmdletBinding()]
    Param(
        [parameter(Mandatory=$true)] [String] $OutDir,
        [parameter(Mandatory=$true)]  [string] $SendDir,
        [parameter(Mandatory=$true)]  [string] $Fname,
        [parameter(Mandatory=$true)]  [string] $Oper
    )

    for ($i=0; $i -lt $g_Config.Iterations; $i++) {
        [int] $portstart = $g_Config.StartPort + ($i * $g_Config.Iterations)
        test_send -Port $portstart -Oper $Oper -SendDir $SendDir -Fname "$Fname.iter$i" -OutDir $OutDir
        test_recv -Port $portstart
    }   
}

function test_lagscope_generate {
    [CmdletBinding()]
    Param(
        [parameter(Mandatory=$true)] [String] $OutDir,
        [parameter(Mandatory=$true)]  [string] $SendDir,
        [parameter(Mandatory=$true)]  [string] $RecvDir
    )

    # Iteration Tests capturing each transaction time
    # - Measures over input samples
    if ($g_Config.PingIterations -gt 0) {
        banner -Msg "Iteration Tests: [tcp] operations per bounded iterations"
        test_operations -Oper "-n$($g_Config.PingIterations)" -OutDir $OutDir -Fname "tcp.i$($g_Config.PingIterations)" -SendDir $SendDir
    }
    # Transactions per 10s
    # - Measures operations per bounded time.
    if ($g_Config.Time -gt 0) {
        banner -Msg "Time Tests: [tcp] operations per bounded time"
        test_operations -Oper "-t$($g_Config.Time)" -OutDir $OutDir -Fname "tcp.t$($g_Config.Time)" -SendDir $SendDir
    }
} # test_lagscope_generate()
function validate_config {
    $isValid = $true
    $int_vars = @('Iterations', 'StartPort', 'Time', 'PingIterations')
    foreach ($var in $int_vars) {
        if (($null -eq $g_Config.($var)) -or ($g_Config.($var) -lt 0)) {
            Write-Host "$var is required and must be greater than or equal to 0"
            $isValid = $false
        }
    }
    return $isValid
} # validate_config()
#===============================================
# External Functions - Main Program
#===============================================
function test_main {
    Param(
        [parameter(Mandatory=$true)]  [string] $DestIp,
        [parameter(Mandatory=$true)]  [string] $SrcIp,
        [parameter(Mandatory=$true)]  [ValidateScript({Test-Path $_ -PathType Container})] [String] $OutDir = "",
        [parameter(Mandatory=$false)] [string] $Config = "Default",
        [parameter(Mandatory=$true)]  [string] $DestDir,
        [parameter(Mandatory=$true)]  [string] $SrcDir

    )
    try {
        input_display
        $allConfig = Get-Content -Path "$PSScriptRoot/lagscope.Config.json" | ConvertFrom-Json
        # get config variables
        [Object] $g_Config = $allConfig.("Lagscope$Config")
        if ($null -eq $g_Config) {
            Write-Host "Lagscope$Config does not exist in ./lagscope/lagscope.Config.json. Please provide a valid config"
            Throw
        }
        if (-Not (validate_config)) {
            Write-Host "Lagscope$Config is not a valid config"
            Throw
        }
        [string] $g_DestIp  = $DestIp.Trim()
        [string] $g_SrcIp   = $SrcIp.Trim()
        [string] $dir       = (Join-Path -Path $OutDir -ChildPath "lagscope")  
        [string] $g_log     = "$dir/LAGSCOPE.Commands.txt"
        [string] $g_logSend = "$dir/LAGSCOPE.Commands.Send.txt"
        [string] $g_logRecv = "$dir/LAGSCOPE.Commands.Recv.txt" 
        [string] $sendDir   = (Join-Path -Path $SrcDir -ChildPath "lagscope")
        [string] $recvDir   = (Join-Path -Path $DestDir -ChildPath "lagscope")

        New-Item -ItemType directory -Path $dir | Out-Null

        test_lagscope_generate -OutDir $dir -SendDir $sendDir -RecvDir $recvDir
    } catch {
        Write-Host "Unable to generate LAGSCOPE commands"
        Write-Host "Exception $($_.Exception.Message) in $($MyInvocation.MyCommand.Name)"
    }
} test_main @PSBoundParameters # Entry Point