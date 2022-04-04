# NetPerfTest-Linux

## Description

NetPerfTest-Linux is a collection of tools used to generate tests, run tests, and collect network configuration, and performance statistics for diagnosis of networking performance issues. 

## Pre-Requisites
These tools are necessary the run the PowerShell scripts in NetPerfTest. Some tools like PuttY, ufw, and SSH client, may already be installed on Linux Systems by default.

* Powershell 6 or higher for Linux
* SSH client and server (OpenSSH Client and Server)
* PuTTTY - specifically plink command
* ufw, or Uncomplicated Firewall

If SSH password authentication is disabled on the VM, the orchestrating machine must have copied its own public ssh key to the destination and source machine.

## Command Generation
Once pre-requisite tools have been installed, we can start the testing process. 
First, we must generate a bunch of relevant networking tests between these machines. 
Now that the folder is created, we're ready to generate the commands using the PERFTEST cmdlet 
The TestUserName is the username of the orchestrating machine to determine the location of the command. 
:

```PowerShell
./PERFTEST.PS1 -DestIp "DestinationMachineIP" -SrcIP "SourceMachineIP" -OutDir "Temp/MyDirectoryForTesting" -DestUserName "DestinationUserName" -SrcUserName "SourceUserName" -TestUserName "TestUserName"
```

The OutDir folder should not contain the home path.

The default configuration for the commands are outlined in Toolname.Config.json.
If you would like you use a different configuration, pass in the name of the configuration. If you would like to make your own configuration, the name of the configuration must start with the toolname and can be added to the respective json file. Refer to Toolname.Config.md for more information on creating json configs.

```PowerShell 
./PERFTEST.PS1 -DestIp "DestinationMachineIP" -SrcIP "SourceMachineIP" -OutDir "Temp/MyDirectoryForTesting" -DestUserName "DestinationUserName" -SrcUserName "SourceUserName" -TestUserName "TestUserName" -Config 'Detail'
```

## Setup

Before proceeding to run the commands/tests that were generated above, we must enable Powershell Remoting over SSH and enable the firewall. This script will automatically enable PowerShell Remoting over SSH, and will thus modify the configuration file (ej. sshd_config) and firewall rules.  There is a cleanup script that is recommended after collecting the results (more on that below, in the Cleanup section).

If you choose to use password authentication, use the switch -KeyAuth.

On Linux machines, you must start Powershell with sudo to elevate the permissions for 
the setup and cleanup or else you will be prompted for a password.

```console
sudo pwsh
```

To setup the machine(s), run the following command on each machine to test (ej. Destination and Source machine)

```PowerShell
SetupTearDown.ps1 -Setup
```

```PowerShell
SetupTearDown.ps1 -Setup -PassAuth
```

## Command Execution and Result Collection

We are now at the phase where we will run the tests against the Source and Destination Machines and collect results for offline troubleshooting.
The scripts use Powershell Remoting via SSH to kick off commands on the two machines to perform the networking tests.
You will need to provide the same Source and Destination IPs as you did for commands generation. In addition you must provide the path to the 
directory of commands that was generated in the Commands Generation phase above. (ej. msdbg.CurrentMachineName.perftest)

RunPerfTool was created as a powershell module with the idea of flexibility with its invocation (invoking from another script versus standalone invocations, etc)

We will thus need to import the Module like this: ```Import-Module -Force .\runPerftool.psm1```
We will then invoke a single function in this module that will process all the commands and run them and gather the results. 
For further help with this function, run ```Get-Help ProcessCommands```

The command to run tests using password authentication is:
```
ProcessCommands -DestIp "DestinationMachineIP" -SrcIp "SourceMachineIP" -CommandsDir "Temp/MyDirectoryForTesting/msdbg.CurrentMachineName.perftest" -SrcIpUserName SrcUserName -DestIpUserName DestUserName -TestUserName TestUserName -PassAuth
```

The command to run tests using public key authentication is:
```
ProcessCommands -DestIp "DestinationMachineIP" -SrcIp "SourceMachineIP" -CommandsDir "Temp/MyDirectoryForTesting/msdbg.CurrentMachineName.perftest" -SrcIpUserName SrcUserName -DestIpUserName DestUserName -TestUserName TestUserName -SrcIpKeyPath SrcPrivateKeyFilePath -DestIpKeyPath DestPrivateKeyFilePath
```

You will be prompted for password for credentials of both the source and destination machine if you do Password Authentication. It is a Secure-string so your password will not be displayed or stored in clear text at any point. Do not include the home path in the command directory.

```
SrcIpPassword? *****
DestIpPassword? *****
```

```PowerShell commands
Import-Module -Force .\runPerftool.psm1
ProcessCommands -DestIp DestinationMachineIP -SrcIp SourceMachineIP -CommandsDir Temp/MyDirectoryForTesting/msdbg.CurrentMachineName.perftest -SrcIpUserName SrcUserName -DestIpUserName DestUserName
# For further help run 
Get-Help ProcessCommands
```

There will be limited output as most of the output will be suppressed or put into a log file in the command directory (CurrentMachineName.log). Note that there will be output from PowerShell Remoting via SSH that is unable to be suppressed about creating an rsa public/private pair, known hosts, authenticated keys, and sudo prompts that are automated in the script. You will not need to provide input to these prompts other than the initial prompt for the password credentials of the source and destination machine. 

You should see the zip files from DestinationMachineIp and SourceMachineIP machines under the 
CommandsDir folder you specified (ej. Temp/MyDirectoryForTesting/msdbg.CurrentMachineName.perftest)

At this point you are done! Don't forget to share the folder contents and run Cleanup step below.

## Cleanup
After finishing running the relevant tests, it is recommended to run cleanup script to undo the steps that were done in the Setup stage. 
To cleanup the machine(s), run the following command on each machine you leveraged for testing (Destination and Source machine)

```PowerShell 
SetupTearDown.ps1 -Cleanup
```

Note that the OpenSSH Server will be turned off and set back the default settings of listening port 22, and allowing password and public key authentication.

You will be prompted for password for the computer you are running the script on to enable to firewall and edit files. It is a Secure-string so your password will not be displayed or stored in clear text at any point.


# Contributing

This project welcomes contributions and suggestions.  Most contributions require you to agree to a
Contributor License Agreement (CLA) declaring that you have the right to, and actually do, grant us
the rights to use your contribution. For details, visit https://cla.opensource.microsoft.com.

When you submit a pull request, a CLA bot will automatically determine whether you need to provide
a CLA and decorate the PR appropriately (e.g., status check, comment). Simply follow the instructions
provided by the bot. You will only need to do this once across all repos using our CLA.

This project has adopted the [Microsoft Open Source Code of Conduct](https://opensource.microsoft.com/codeofconduct/).
For more information see the [Code of Conduct FAQ](https://opensource.microsoft.com/codeofconduct/faq/) or
contact [opencode@microsoft.com](mailto:opencode@microsoft.com) with any additional questions or comments.
