###############################################################################
# Version 1.1 created by Mike Rudyi
# NutanixCMDletsPSSnapin required
# 
# Usage >WindowsNGTInstall.ps1 -vmname "<vmname or list in file>" -clusterServer "<cluster dns name or ip>" -errorlogpath "<optional paramater to save errors to a file>"
#
# Note: The user running this script must winrm access to the vms that are installing ngt. i.e you should launch this script with a domain account and then provide
# the cluster credentials when prompted.
###############################################################################

param (
[Parameter(Mandatory=$true)][string]$vmname,
[Parameter(Mandatory=$true)][string]$clusterServer,
[bool]$showInfoMessages = $true,
[string]$errorlogpath
)

Add-PSSnapin NutanixCMDletsPSSnapin

$ngtInstallParameters = {
$cdRom = (Get-WmiObject Win32_LogicalDisk -Filter "VolumeName='NUTANIX_TOOLS'").DeviceID
$ntnxsetupPath = Join-Path $cdRom '\setup.exe'
$setupArgs = '/quiet ACCEPTEULA=yes /norestart'
Start-Process -FilePath $ntnxsetupPath -ArgumentList $setupArgs -Wait
}

###############################################################################
#
# Functions
#
###############################################################################

function connectToCluster {
    $clusterCreds = Get-Credential -Message "Provide credentials to the $clusterServer cluster in the <user>@yourDomain.org format"
    Connect-NutanixCluster -Server $clusterServer -Password $clustercreds.GetNetworkCredential().SecurePassword -UserName $clustercreds.username -AcceptInvalidSSLCerts -ForcedConnection
    $clusterCreds = $null
    }

function messenger ($message) {
    if ($showInfoMessages){
        write-output $message
    }
}

function errorLogger ($errormsg) {
    if ($errorlogpath){
        Add-Content -Value "$(Get-Date -Format o) $errormsg" -Path $errorlogpath
        write-output $errormsg
    }
    else {
        write-output $errormsg
    }
}

function enableNGT ($d){
    messenger "Enabling NGT post install."
    $Timeout2 = 60
    $timer2 = [Diagnostics.Stopwatch]::StartNew()
    while (($timer2.Elapsed.TotalSeconds -lt $Timeout2) -and (!($d |Get-NTNXGuestTool).installedVersion)) {
        Start-Sleep -Seconds 1
    }
    if (!($d |Get-NTNXGuestTool).installedVersion) {
        $timer2.Stop()
        errorLogger "Could not detect NGT status within $timeout seconds on $($d.vmName). Aborting the enabling task. Verify install and enable in Prism."
        }
    else {
        $timer2.Stop()
        $d | Set-NTNXGuestTool -Enabled $true
    }
}

function installNGT ($b) {
    messenger "Waiting for install disk to become available on $($b.vmName)."
    $Timeout = 60
    $timer = [Diagnostics.Stopwatch]::StartNew()
    while (($timer.Elapsed.TotalSeconds -lt $Timeout) -and (!(Invoke-Command -ComputerName $b.vmName -ScriptBlock {(Get-WmiObject Win32_LogicalDisk -Filter "VolumeName='NUTANIX_TOOLS'").DeviceID}))) {
        Start-Sleep -Seconds 1
    }
    if (!(Invoke-Command -ComputerName $b.vmName -ScriptBlock {(Get-WmiObject Win32_LogicalDisk -Filter "VolumeName='NUTANIX_TOOLS'").DeviceID})) {
        $timer.Stop()
        errorLogger "NGT Disk failed to mount within $timeout seconds. Aborting install on $($b.vmName)."
        }
    else {
        $timer.Stop()
        messenger "Installing NGT on $($b.vmName). Please wait."
        Invoke-Command -ComputerName $b.vmName -ScriptBlock $ngtInstallParameters
        enableNGT $b
    }
}

function mountTools ($vmObject) {
    if ($vmObject.powerstate -eq "on") {
        try{
            $vmObject | Mount-NTNXGuestTool
            installNGT $vmObject    
        }
        catch {
            errorLogger "Could not mount Nutanix guest tools on $($vmObject.vmname).  Verify no other image is mounted on the CDRom drive."
        }
    }
    else {
        errorLogger "$($vmObject.vmname) appears to be off. Aborting install!"
        }
}

function checkNGTMount ($vmguest) {
    try {
        $vmGuestToolInfo = $vmguest | Get-NTNXGuestTool
        if (!$vmGuestToolInfo.installedVersion){
            messenger "Nutanix Guest Tools not Installed on $($vmguest.vmName). Locating install disk."
            if ($vmGuestToolInfo.toolsMounted) {            
                installNGT $vmguest                                          
            }
            else {
                messenger "Guest tools disk not mounted on $($vmguest.vmName). Attempting to mount now."
                mountTools $vmguest  
            }        
        }
        else {
            messenger "Nutanix guest tools version $($vmGuestoolinfo.installedversion) installed on $($vmguest.vmName). Nothing for me to do here."
        }
    }
    catch {
        messenger "Nutanix guest tools not enabled on $($vmguest.vmName).  Attempting to enable and mount install disk."
        mountTools $vmguest
    }
}

function checkVmname ($nameTocheck) {
    $namecheck = Get-NTNXVM | Where-Object vmName -eq $nameTocheck
    if ($namecheck) {
        checkNGTMount $namecheck        
    }
    else {
        errorLogger "$nameTocheck could not be found on cluster $clusterServer"
    }
    
}

function listOrNot ($inpt) {
    if (Test-Path $inpt){
            $vmList = Get-Content -Path $inpt
            foreach ($objName in $vmList){
                checkVmname $objName
            }
        }
    else {
        checkVmname $inpt
    }

}

###############################################################################
#
# Program Loop
#
###############################################################################

#Ensures the script doesn't attempt to run against a stale cluster connection
Disconnect-NTNXCluster *

connectToCluster
listOrNot $vmname

###############################################################################
#
# Cleanup
#
###############################################################################

Disconnect-NTNXCluster *
