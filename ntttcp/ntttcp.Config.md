# Ntttcp Config Guidelines
Any optional variables will be omitted
```
"Ntttcp**NameOfConfig**": { # Name of config must start with Ntttcp
    "Iterations"  : **Int: Number of command iterations**,
    "StartPort"   : **Int: Starting Destination Port Number**,
    "tcp" : { # Optional
        "BufferLen"  : **Array: List of buffer size for tcp in n[KMG] Bytes**,
        "Connections": **Array: List of number of receiver ports for tcp**,
        "Options"    : **String: Additional options for tcp commands e.g. --show-tcp-retrans**
    },
    "udp" : { # Optional
        "BufferLen"  : **Array: List of buffer size for udp in n[KMG] Bytes**,
        "Connections": **Array: List of number of receiver ports for udp**,
        "Options"    : **String: Additional options for udp commands**
    },
    "Warmup"      : **Int: Warm-up time in seconds**,
    "Cooldown"    : **Int: Cooldown time in seconds**,
    "Runtime"        : **Int: Time of Test Duration in seconds**,
    "RecvOptions" : **String: Additional options for receiver commands**,
    "SendOptions" : **String: Additional options for sender commands**
}
```