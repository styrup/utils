[CmdletBinding()]
param (
    [Parameter()]
    [string]
    $OVFPath,
    [Parameter()]
    [string]
    $VMName,
    [Parameter()]
    [string]
    $VMUsername,
    [Parameter()]
    [string]
    $VMUserPublicKey,
    [Parameter()]
    [string]
    $VMUserFallbackPW,
    [Parameter()]
    [int]
    $VMDiskSizeGB,
    [Parameter()]
    [int]
    $VMMemoryGB,
    [Parameter()]
    [string]
    $VMDataStoreName,
    [Parameter()]
    [string]
    $ESXHost,
    [Parameter()]
    [string]
    $ESXUsername,
    [Parameter()]
    [string]
    $ESXUserPW,
    [Parameter()]
    [string]
    $ESXCloudInitDataStoreName



    
)


$ParameterList = (Get-Command -Name $MyInvocation.InvocationName).Parameters
foreach ( $ParameterKey in $ParameterList.Keys ) {
    $ParameterValue = (Get-Variable $ParameterKey -ErrorAction SilentlyContinue)
    if ($null -ne $ParameterValue) {
        if ($ParameterValue.Value -eq "") { 
            $EnvVar = Get-Item -Path env:$ParameterKey -ErrorAction Ignore
            if ($null -ne $EnvVar) {
                set-Variable -Name "$($ParameterKey)" -Value $EnvVar.Value
            }
            else {
                Write-Host "Missing argument or environment variable: $ParameterKey"
                exit 1
            }
        }
    }
}

    
if (-not (Test-Path -Path $OVFPath)) {
    Write-Error "OVF file ($($OVFPath)) not found!"
    return 1
}


$viserver = $null
$viserver = Connect-VIServer -Server $ESXHost -User $ESXUsername -Password $ESXUserPW -Force -ErrorAction Ignore
if($null -eq $viserver){
    Write-Host "Error in connection to ESX host."
    return
}


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

