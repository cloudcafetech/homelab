resource "proxmox_vm_qemu" "ocpmaster1" {
  depends_on = [ 
     jumphost,
     bootstrap
  ]

  name                      = "var.ocpmaster1_hn"
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
    macaddr = var.ocp_master01_mac
  }
}

resource "proxmox_vm_qemu" "ocpmaster2" {
  depends_on = [ 
     jumphost,
     bootstrap
  ]

  name                      = "var.ocpmaster2.hn"
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
    macaddr = var.ocp_master02_mac
  }
}

resource "proxmox_vm_qemu" "ocpmaster3" {
  depends_on = [ 
     jumphost,
     bootstrap
  ]

  name                      = "var.ocpmaster3.hn"
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
    macaddr = var.ocp_master03_mac
  }
}
