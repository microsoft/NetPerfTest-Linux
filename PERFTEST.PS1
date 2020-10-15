#===============================================
# Script Input Parameters Enforcement
#===============================================
Param(
    [parameter(Mandatory=$false)] [switch] $Detail = $false,
    [parameter(Mandatory=$false)] [switch] $Diag   = $false,
    [parameter(Mandatory=$false)] [Int]    $Iterations = 1,
    [parameter(Mandatory=$false)] [ValidateSet('Sampling','Testing')] [string] $Config = "Sampling",
    [parameter(Mandatory=$true)]  [string] $DestIp,
    [parameter(Mandatory=$true)]  [string] $SrcIp,
    [parameter(Mandatory=$true)]  [String] $OutDir = "",
    [parameter(Mandatory=$true)]  [string] $DestUserName,
    [parameter(Mandatory=$true)]  [string] $SrcUserName,
    [parameter(Mandatory=$true)]  [string] $TestUserName

)
$scriptName = $MyInvocation.MyCommand.Name 

function input_display {
    $g_path = Get-Location

    Write-Host "============================================"
    Write-Host "$g_path\$scriptName"
    Write-Host " Inputs:"
    Write-Host "  -Detail     = $Detail"
    Write-Host "  -Diag       = $Diag"
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

function env_normalize {
    [CmdletBinding()]
    Param(
        [parameter(Mandatory=$true)] [String] $OutDir
    )

    $baseDir = if (-not [String]::IsNullOrWhiteSpace($OutDir)) {
                   if (Test-Path $OutDir) {
                       (Resolve-Path $OutDir).Path # full path
                   } 
                   else {
                       throw "-> The directory ""$OutDir"" does not exist."
                   }
               } 
    $computername = hostname
    $workDirName = "msdbg.$computername.perftest"

    return (Join-Path $baseDir $workDirName).TrimEnd("\")
} # env_normalize()

function remote_env_normalize {
    [CmdletBinding()]
    Param(
        [parameter(Mandatory=$true)] [String] $OutDir
    )
    $computername = hostname
    $workDirName = "msdbg.$computername.perftest"

    return (Join-Path $OutDir $workDirName).TrimEnd("\")
} # remote_env_normalize()

function env_create {
    [CmdletBinding()]
    Param(
        [parameter(Mandatory=$true)] [String] $OutDir
    )

    # Attempt to create working directory, fail gracefully otherwise
    try {
        New-Item -ItemType directory -Path $OutDir -ErrorAction Stop | Out-Null
    } catch {
        throw "-> Failed to create directory ""$OutDir"" because " + $error[0]
    }
} # env_create()

function env_destroy {
    [CmdletBinding()]
    Param(
        [parameter(Mandatory=$true)] [String] $OutDir
    )

    If (Test-Path $OutDir) {
        # Careful - Deletes $OurDir and all its contents
        Remove-Item $OutDir -Recurse -Force # Careful - Deletes $OurDir and all its contents
    }
} # env_destroy()


#===============================================
# External Functions - Main Program
#===============================================
function test_main {
    Param(
        [parameter(Mandatory=$false)] [switch] $Detail     = $false,
        [parameter(Mandatory=$false)] [switch] $Diag       = $false,
        [parameter(Mandatory=$false)] [Int]    $Iterations = 1,
        [parameter(Mandatory=$false)] [ValidateSet('Sampling','Testing')] [string] $Config = "Sampling",
        [parameter(Mandatory=$true)]  [string] $DestIp,
        [parameter(Mandatory=$true)]  [string] $SrcIp,
        [parameter(Mandatory=$true)]  [String] $OutDir = "",
        [parameter(Mandatory=$true)]  [string] $DestUserName,
        [parameter(Mandatory=$true)]  [string] $SrcUserName,
        [parameter(Mandatory=$true)]  [string] $TestUserName
    )
    Clear-Host
    input_display

    $start   = Get-Date
    $version = "2020.09.28.0" # Version within date context

    Write-Host $start
    Write-Host $version

    [int]    $g_iters     = $Iterations
    [bool]   $g_detail    = $Detail
    [bool]   $g_diag      = $Diag
    [string] $g_config    = $Config
    [string] $g_DestIp    = $DestIp
    [string] $g_SrcIp     = $SrcIp

    $DestDir = remote_env_normalize "/home/$DestUserName/$OutDir"
    $SrcDir = remote_env_normalize "/home/$SrcUserName/$OutDir"
    $OutDir = "/home/$TestUserName/$OutDir"

    $workDir = env_normalize -OutDir $OutDir
    Write-Host $workDir

    env_destroy -OutDir $workDir
    env_create  -OutDir $workDir


    # lagscope does not have detail 
    ./lagscope/lagscope.TESTGEN.ps1   -DestIp $g_DestIp -SrcIp $g_SrcIp -OutDir $workDir -Iterations $g_iters -DestDir $DestDir -SrcDir $SrcDir
    ./ntttcp/ntttcp.TESTGEN.ps1 -DestIp $g_DestIp -SrcIp $g_SrcIp -OutDir $workDir -Detail:$g_detail -Iterations $g_iters -Config $g_config -DestDir $DestDir -SrcDir $SrcDir

    } test_main @PSBoundParameters # Entry Point