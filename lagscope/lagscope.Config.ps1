$lagscopeDefault = @{
    '-Iterations'     = 5
    '-StartPort'      = 50001
    '-BufferSize'     = @(65536)
    '-MessageSize'    = 4
    '-Time'           = 10
    '-PingIterations' = 20000   
    '-Options'        = $null
} 

$lagscopeAzure = @{
    '-Iterations'     = 5
    '-StartPort'      = 50001
    '-BufferSize'     = @(65536)
    '-MessageSize'    = 4
    '-PingIterations' = 20000
    '-Options'        = $null
} 