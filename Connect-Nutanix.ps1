function Connect-Nutanix {
    
    #first check if the NutanixCmdletsPSSnapin is loaded, load it if its not, Stop script if it fails to load
    if ( (Get-PSSnapin -Name NutanixCmdletsPSSnapin -ErrorAction SilentlyContinue) -eq $null ) {Add-PsSnapin NutanixCmdletsPSSnapin -ErrorAction Stop}
 $SecurePassword = ${env:Password} | ConvertTo-SecureString -AsPlainText -Force
        if($env:Cluster){$NutanixCluster = $env:Cluster}
        else{  Write-Output " Please select Cluster to connect"
                Break}
        $connection = Connect-NutanixCluster -server $NutanixCluster -username ${env:User} -password $SecurePassword -AcceptInvalidSSLCerts
        if ($connection.IsConnected){
            #connection success
            Write-Host "Connected to $($connection.server)" -ForegroundColor Green
        }
        else{
            #connection failure, stop script
            Write-Warning "Failed to connect to $NutanixCluster"
            Break
        }
}Connect-Nutanix

Function Create-NTNXVM {

Write-Host "Checking if VM already exists..."
if (!(Get-NTNXVM -SearchString $env:VMName).vmid){
    #convert GB to MB for RAM
    [Int64]$Memory = ([Int64]$env:Memory * 1024)
    #setup the nicSpec
    $nicSpec = New-NTNXObject -Name VMNicSpecDTO
    #find the right network to put the VM on
    $network = (Get-NTNXNetwork | ?{$_.Name -eq $env:Network})
    if($network){$nicSpec.networkuuid = $network.uuid}
    else{
        Write-Warning "Specified VLANID: $env:Network, does not exist, it needs to be created in Prism, exiting"
        Break
    }
    #request an IP, if specified
    if($env:IP){$nicSpec.requestedIpAddress = $env:IP}
    #setup the VM's disk
    $vmDisk = New-NTNXObject -Name VMDiskDTO
    switch ($env:OS){

        "Server 2016" { $disk = '2016template-sysprepped' }
        "Server 2019" { $disk = '2019template-sysprepped' } 
        }
    if($env:OS){
        #setup the image to clone from the Existing VM
        $diskCloneSpec = New-NTNXObject -Name VMDiskSpecCloneDTO
        #check to make sure specified Existing VM Exists
        $diskToClone = ((Get-NTNXVMDisk -Vmid (Get-NTNXVM -searchstring $disk).vmId) | ? {!$_.isCdrom})
        if($diskToClone){$diskCloneSpec.vmDiskUuid = $diskToClone.VmDiskUuid}
        else{
            Write-Warning "Specified Existing VM Name: $disk, does not exist, exiting"
            Break
        }
        #setup the new disk from the Cloned Existing VM
        $vmDisk.vmDiskClone = $diskCloneSpec
    }
    
    #adds any AdditionalVolumes if specified.
    [Int64]$env:HardDrive2 = $HardDrive2
    if($HardDrive2){
        if(!($vmDisk[1])){$vmDisk = @($vmDisk)}
        foreach($volume in $env:HardDrive2){
            $diskCreateSpec = New-NTNXObject -Name VmDiskSpecCreateDTO
            $diskCreateSpec.containerUuid = (Get-NTNXContainer -SearchString "default").containerUuid
            $diskCreateSpec.sizeMb = $volume.Size * 1024
            $AdditionalvmDisk = New-NTNXObject -Name VMDiskDTO
            $AdditionalvmDisk.vmDiskCreate = $diskCreateSpec
            $vmDisk += $AdditionalvmDisk
        }
    }

    #Create the VM
    Write-Host "Creating $env:VMName on $env:Cluster..."
    $createJobID = New-NTNXVirtualMachine -MemoryMb $Memory -Name $env:VMName -NumVcpus $env:vCPU -NumCoresPerVcpu 1 -VmNics $nicSpec -VmDisks $vmDisk -Description $env:Description -ErrorAction Continue
    if($createJobID){Write-Host "Created $env:VMName on $env:Cluster" }
    else{
        Write-Warning "Couldn't create $env:VMName on $env:Cluster, exiting"
        Break
    }
    #now wait for the VM to be created and then power it on
    Function VM-Poweron{

    Try{
        $count = 0
        #wait up to 30 seconds, trying every 5 seconds, for the vm to be created
        while (!$VMidToPowerOn -and $count -le 6){
            Write-Host "Waiting 5 seconds for $env:VMName to finish creating..."
            Start-Sleep 5
            $VMidToPowerOn = (Get-NTNXVM -SearchString $env:VMName).vmid
            $count++
        }
        }Catch{}
        
        #now power on the VM
            Write-Host "Powering on $env:VMName on $env:Cluster..."
            $poweronJobID = Set-NTNXVMPowerOn -Vmid $VMidToPowerOn
            if($poweronJobID){Write-Host "Successfully powered on $env:VMName on $env:Cluster"}
            else{
                Write-Warning "Couldn't power on $env:VMName on $env:Cluster, exiting"
                Break
            }
        }VM-Poweron
}
else{
    Write-Host "$VMName already exists on $ClusterName, exiting"
    Break
}

Disconnect-NTNXCluster -Servers *

}Create-NTNXVM
