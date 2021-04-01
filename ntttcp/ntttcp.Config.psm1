$ntttcpDefault = @{
    '-Iterations'     = 6
    '-StartPort'      = 50002
    '-BufferTcp'      = @(65536)
    '-BufferUdp'      = @(1450)
    '-Warmup'         = 2
    '-Cooldown'       = 2
    '-Time'           = 60
    '-ConnectionsTcp' = @(64)
    '-ConnectionsUdp' = @(64)
    '-Options'        = '-e'
}

$ntttcpAzure = @{
    '-Iterations'     = 6
    '-StartPort'      = 50002
    '-BufferTcp'      = @(65536)
    '-BufferUdp'      = @(1450)
    '-Warmup'         = 2
    '-Cooldown'       = 2
    '-Time'           = 60 
    '-ConnectionsTcp' = @(64)
    '-ConnectionsUdp' = @(64)
    '-Options'        = '-e'
}

$ntttcpDetail = @{
    '-Iterations'     = 6
    '-StartPort'      = 50002
    '-BufferTcp'      = @(65536)
    '-BufferUdp'      = @(1450)
    '-Warmup'         = 2
    '-Cooldown'       = 2
    '-Time'           = 60
    '-ConnectionsTcp' = @(1, 2, 4, 8, 16, 32, 64, 128, 256, 512)
    '-ConnectionsUdp' = @(1, 2, 4, 8, 16, 32, 64, 128, 256, 512)
    '-Options'        = '-e'
}