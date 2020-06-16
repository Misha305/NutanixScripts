# A collection of scripts to perform usefull Nutanix funsctions using Posh

USAGE
WindowsNGTInstall.ps1 -vmname "<vmname or list in file>" -clusterServer "<cluster dns name or ip>" -errorlogpath "<optional paramater to save errors to a file>" -$showInfoMessages <Default $true>

Parameters
    vmname - (required) Specify a Vmname or a vm list i.e a text a file with a list of vms line by line. The vmnames must coincide with the vmnames in AHV
    clusterServer - (required) The dns name or IP of your prism elements cluster.
    errorLogPath - (optional) Specify a full path to record errors.
    showInfoMessages - (optional) set to $false to not write-out any process messages. Default value is $true.