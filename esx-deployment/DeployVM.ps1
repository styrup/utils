[CmdletBinding()]
param (
    [Parameter()]
    [string]
    $OVFPath = $env:OVFPath ,
    [Parameter()]
    [string]
    $VMName = $env:VMNAME,
    [Parameter()]
    [string]
    $VMUsername = $env:VMUSERNAME,
    [Parameter()]
    [string]
    $VMUserPublicKey = $env:VMUSERPUBLICKEY,
    [Parameter()]
    [string]
    $VMUserFallbackPW = $env:VMUSERFALLBACKPW,
    [Parameter()]
    [int]
    $VMDiskSizeGB = $env:VMDISKSIZEGB,
    [Parameter()]
    [int]
    $VMMemoryGB = $env:VMMEMORYGB,
    [Parameter()]
    [string]
    $VMDataStoreName = $env:VMDATASTORENAME,
    [Parameter()]
    [string]
    $ESXHost = $env:ESXHOST,
    [Parameter()]
    [string]
    $ESXUsername = $env:ESXUSERNAME,
    [Parameter()]
    [string]
    $ESXUserPW = $env:ESXUSERPW,
    [Parameter()]
    [string]
    $ESXCloudInitDataStoreName = $env:ESXCLOUDINITDATASTORENAME



    
)

$ParameterList = (Get-Command -Name $MyInvocation.InvocationName).Parameters
foreach ( $ParameterKey in $ParameterList.Keys ) {
    $ParameterValue = (Get-Variable $ParameterKey -ErrorAction SilentlyContinue)
    if ($null -ne $ParameterValue) {
        if ($ParameterValue.Value -eq "") { 
            # Evt. lav tjek for env her, så behøver man dem ikke i toppen.
            Write-Host "Missing argument or environment variable: $ParameterKey"
            exit 1
        }
    }
}

    
    


return

<#
Disse ting skal sættes som env for at den bliver mere docker venlig.
$OVFPath
    Husk at tjekke for om filen er der.
$VMNName
$VMUsername
$VMUserPublicKey
$VMUserFallbackPW
$VMDiskSizeGB
$VMMemoryGB
$VMDataStoreName
$ESXHost
    Tjek for forbindelse.
$ESXUser
$ESXPW
$ESXCloudInitDataStoreName

Skift til US.

#>
$ovfPath = ".\ubuntu-bionic-18.04-cloudimg.ovf"

Connect-VIServer -Server $ESXHost -User $ESXUsername -Password $ESXUserPW
## Tjek for fejl.

$DirectorySeparator = $([IO.Path]::DirectorySeparatorChar)
$vmcdfolder = "$($pwd.path)$($DirectorySeparator)$VMName-cd"
$vmisofile = "$($pwd.path)$($DirectorySeparator)$VMName-seed.iso"
$metadatafile = "$vmcdfolder$($DirectorySeparator)meta-data"
$userdatafile = "$vmcdfolder$($DirectorySeparator)user-data"

mkdir $vmcdfolder
"instance-id: iid-local01" | Out-File -FilePath $metadatafile -Encoding utf8 -Append
"local-hostname: cloudimg" | Out-File -FilePath $metadatafile -Encoding utf8 -Append

$userData = Get-Content .\user-data-template
$newUSerData = $userData | ForEach-Object { $_ -replace "CIHOSTNAME", $VMName -replace "CIPASSWORD", $VMUserFallbackPW -replace "CIUSER", $VMUsername -replace "CIKEY", $VMUserPublicKey }
[IO.File]::WriteAllLines($userdatafile, $newUSerData)


$dataSrcFolder = "$vmcdfolder$($DirectorySeparator)"
xorrisofs -r -J -volid cidata -o $vmisofile $dataSrcFolder

$SSD = Get-Datastore -Name $ESXCloudInitDataStoreName
if ($null -eq (Get-PSDrive -Name ds -ErrorAction Ignore)) {
    New-PSDrive -Name ds -PSProvider VimDatastore -Root "\" -Location $SSD
}
## Tjek for fejl.

Copy-DatastoreItem -Item $vmisofile -Destination ds:\cloud-init\

$VMDS = Get-Datastore -Name $VMDataStoreName
Import-VApp $ovfPath -Name $vmname  -VMHost (Get-VMHost) -Datastore $VMDS -Location (Get-VMHost) -DiskStorageFormat Thin
# todo: her skal man bruge id eller noget.
$vm = Get-VM -Name $vmname
$vm | Get-CDDrive | Set-CDDrive -IsoPath "[$($SSD.Name)] cloud-init\$VMName-seed.iso" -Confirm:$false -StartConnected:$true
if ($diskSizeGB -ge 10) {
    $vm | Get-HardDisk | Set-HardDisk -CapacityGB $VMDiskSizeGB -Confirm:$false
}
if ($memoryGB -ge 1) {
    $vm | VMware.VimAutomation.Core\Set-VM -MemoryGB $VMMemoryGB -Confirm:$false
}
$vm | Start-VM

$vm = Get-VM -Name $VMName
Write-Host "Waiting for VMTools"
while ($vm.Guest.ExtensionData.ToolsRunningStatus -ne "guestToolsRunning") {
    Write-Host "." -NoNewline
    Start-Sleep -Seconds 2
    $vm = Get-VM -Name $VMName
}
Write-Host ""

Write-Host "VMTools running, waiting for hostname"
while ($vm.Guest.HostName.Length -eq 0) {
    Write-Host "." -NoNewline
    Start-Sleep -Seconds 2
    $vm = Get-VM -Name $VMName
}
Write-Host "Hostname found"
Write-Host "Rebooting for removal of CDROM drive."
$vm | Shutdown-VMGuest -Confirm:$false
while ($vm.PowerState -ne "PoweredOff") {
    Write-Host "." -NoNewline
    Start-Sleep -Seconds 2
    $vm = Get-VM -Name $VMName
}
$vm | Get-CDDrive | Set-CDDrive -NoMedia -Confirm:$false -StartConnected:$false

$vm | Start-VM

$vm = Get-VM -Name $vmname
Write-Host "Waiting for VMTools"
while ($vm.Guest.ExtensionData.ToolsRunningStatus -ne "guestToolsRunning") {
    Write-Host "." -NoNewline
    Start-Sleep -Seconds 2
    $vm = Get-VM -Name $VMName
}
Write-Host ""

Write-Host "VMTools running, waiting for hostname"
while ($vm.Guest.HostName.Length -eq 0) {
    Write-Host "." -NoNewline
    Start-Sleep -Seconds 2
    $vm = Get-VM -Name $VMName
}

Get-VM -Name $VMName | Select-Object -ExpandProperty Guest | Format-List *
Remove-Item -Path $vmcdfolder -Recurse -Force -Confirm:$false
Remove-Item -Path $vmisofile -Force -Confirm:$false
# todo:
# måske skal cloud-init reboote en ekstra gang.
# måske send besked?
# slet mappe og iso og fil på datastore.

