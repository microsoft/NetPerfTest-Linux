$lagscopeDefault = @{
    '-Iterations'     = 5
    '-StartPort'      = 50001
    '-Time'           = 10
    '-PingIterations' = 20000   
    '-Options'        = $null
} 

$lagscopeAzure = @{
    '-Iterations'     = 5
    '-StartPort'      = 50001
    '-Time'           = 0
    '-PingIterations' = 20000
    '-Options'        = $null
} 