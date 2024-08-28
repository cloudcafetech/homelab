resource "proxmox_vm_qemu" "ocpworker1" {
  depends_on = [ 
    jumphost,
    ocpmaster1
 ]

  name                      = "var.ocpworker1_hn"
  target_node               = var.pve_node_name
  cpu                       = "host"  
  agent                     = 0
  cores                     = 4
  memory                    = 6114
  boot                      = "order=scsi0;ide2;net0" 
  onboot                    = true
  scsihw                    = "virtio-scsi-pci"
  bootdisk                  = "scsi0"
  disk {
    size    = "40G"
    type    = "scsi"
    storage = "local-lvm"
    #iothread = 1
  }
  network {
    model   = "virtio"
    bridge  = vmbr0
    macaddr = var.ocp_worker01_mac
  }
}

resource "proxmox_vm_qemu" "ocpworker2" {
  depends_on = [ 
    jumphost,
    ocpmaster1
 ]

  name                      = "var.ocpworker2_hn"
  target_node               = var.pve_node_name
  cpu                       = "host"  
  agent                     = 0
  cores                     = 4
  memory                    = 6114
  boot                      = "order=scsi0;ide2;net0" 
  onboot                    = true
  scsihw                    = "virtio-scsi-pci"
  bootdisk                  = "scsi0"
  disk {
    size    = "40G"
    type    = "scsi"
    storage = "local-lvm"
    #iothread = 1
  }
  network {
    model   = "virtio"
    bridge  = vmbr0
    macaddr = var.ocp_worker02_mac
  }
}
