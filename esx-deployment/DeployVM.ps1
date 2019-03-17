param (
    [Parameter(Mandatory = $true)]
    [string]$vmname,
    [int]$diskSizeGB,
    [int]$memoryGB
)
#$ovfPath = "C:\tmp\Cloud-init\os\bionic-server-cloudimg-amd64\ubuntu-bionic-18.04-cloudimg.ovf'"
$ovfPath = ".\ubuntu-bionic-18.04-cloudimg.ovf"
Connect-VIServer -Server 192.168.1.200 -User root -Password VMware1!        

$DirectorySeparator = $([IO.Path]::DirectorySeparatorChar)
$vmcdfolder = "$($pwd.path)$($DirectorySeparator)$vmname-cd"
$vmisofile = "$($pwd.path)$($DirectorySeparator)$vmname-seed.iso"
$metadatafile = "$vmcdfolder$($DirectorySeparator)meta-data"
$userdatafile = "$vmcdfolder$($DirectorySeparator)user-data"

mkdir $vmcdfolder
"instance-id: iid-local01" | Out-File -FilePath $metadatafile -Encoding utf8 -Append
"local-hostname: cloudimg"| Out-File -FilePath $metadatafile -Encoding utf8 -Append

$userData = Get-Content .\user-data-template
$newUSerData = $userData | ForEach-Object {$_.replace("HOSTNAME", $vmname)}
[IO.File]::WriteAllLines($userdatafile, $newUSerData)


$dataSrcFolder = "$vmcdfolder$($DirectorySeparator)"
xorrisofs -r -J -volid cidata -o $vmisofile $dataSrcFolder

#& 'C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\x86\Oscdimg\oscdimg.exe' -j1 -lcidata "$vmcdfolder\" $vmisofile

$SSD = Get-Datastore -Name SSD
if ($null -eq (Get-PSDrive -Name ds -ErrorAction Ignore)) {
    New-PSDrive -Name ds -PSProvider VimDatastore -Root "\" -Location $SSD
}
Copy-DatastoreItem -Item $vmisofile -Destination ds:\cloud-init\


Import-VApp $ovfPath -Name $vmname  -VMHost (Get-VMHost) -Datastore $SSD -Location (Get-VMHost) -DiskStorageFormat Thin
# todo: her skal man bruge id eller noget.
$vm = Get-VM -Name $vmname
$vm | Get-CDDrive | Set-CDDrive -IsoPath "[$($SSD.Name)] cloud-init\$vmname-seed.iso" -Confirm:$false -StartConnected:$true
if ($diskSizeGB -ge 10) {
    $vm | Get-HardDisk | Set-HardDisk -CapacityGB $diskSizeGB -Confirm:$false
}
if ($memoryGB -ge 1) {
    $vm | VMware.VimAutomation.Core\Set-VM -MemoryGB $memoryGB -Confirm:$false
}
$vm | Start-VM

$vm = Get-VM -Name $vmname
"Venter paa Tools"
while ($vm.Guest.ExtensionData.ToolsRunningStatus -ne "guestToolsRunning") {
    Write-Host "." -NoNewline
    Start-Sleep -Seconds 2
    $vm = Get-VM -Name $vmname
}
Write-Host ""

"Tools oppe, venter paa hostnavn"
while ($vm.Guest.HostName.Length -eq 0) {
    Write-Host "." -NoNewline
    Start-Sleep -Seconds 2
    $vm = Get-VM -Name $vmname
}
"Hostnavn fundet"
"Genstarter for at fjerne cdrom"
$vm | Shutdown-VMGuest -Confirm:$false
while ($vm.PowerState -ne "PoweredOff") {
    Write-Host "." -NoNewline
    Start-Sleep -Seconds 2
    $vm = Get-VM -Name $vmname
}
$vm | Get-CDDrive | Set-CDDrive -NoMedia -Confirm:$false -StartConnected:$false

$vm | Start-VM

$vm = Get-VM -Name $vmname
"Venter paa Tools"
while ($vm.Guest.ExtensionData.ToolsRunningStatus -ne "guestToolsRunning") {
    Write-Host "." -NoNewline
    Start-Sleep -Seconds 2
    $vm = Get-VM -Name $vmname
}
Write-Host ""

"Tools oppe, venter paa hostnavn"
while ($vm.Guest.HostName.Length -eq 0) {
    Write-Host "." -NoNewline
    Start-Sleep -Seconds 2
    $vm = Get-VM -Name $vmname
}
"Hostnavn fundet"

Get-VM -Name $vmname | Select-Object -ExpandProperty Guest | fl *
Remove-Item -Path $vmcdfolder -Recurse -Force -Confirm:$false
Remove-Item -Path $vmisofile -Force -Confirm:$false
# todo:
# måske skal cloud-init reboote en ekstra gang.
# måske send besked?
# slet mappe og iso og fil på datastore.

