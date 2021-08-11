# LagscopeConfig Guidelines
Any optional variables will be omitted
```
    "Lagscope**ConfigName**": { # Name of config must start with Lagscope
        "Iterations"     : **Int: Number of command iterations**,
        "StartPort"      : **Int: Starting Server Port Number**,
        "Time"           : **Int: Test Duration**, # set to 0 to omit
        "PingIterations" : **Int: Ping Iteration**, # set to 0 to omit
        "Options"        : **String: Additional options for sender commands**
    },
```