resource "proxmox_vm_qemu" "ocpinfra1" {
  depends_on = [ 
    jumphost,
    ocpmaster1
 ]

  name                      = var.ocpinfra1_hn
  target_node               = var.pve_node_name
  vmid                      = var.ocp_infra02_ip
  cpu                       = "host"  
  agent                     = 0
  cores                     = 4
  memory                    = 6114
  boot                      = "order=scsi0;ide2;net0"
  pxe                       = true
  onboot                    = true
  scsihw                    = "virtio-scsi-pci"
  bootdisk                  = "scsi0"
  disks {
    scsi {
      scsi0 {
        disk {
          discard = true
          emulatessd = true
          storage = "local-lvm"
          size = 40
        }
      }
    }
  }
  network {
    bridge = "vmbr0"
    model = "virtio"
    macaddr = var.ocp_infra01_mac
  }
}

resource "proxmox_vm_qemu" "ocpinfra2" {
  depends_on = [ 
    jumphost,
    ocpmaster1
 ]

  name                      = "var.ocpinfra2_hn"
  target_node               = var.pve_node_name
  vmid                      = var.ocp_infra02_ip
  cpu                       = "host"  
  agent                     = 0
  cores                     = 4
  memory                    = 6114
  boot                      = "order=scsi0;ide2;net0"
  pxe                       = true
  onboot                    = true
  scsihw                    = "virtio-scsi-pci"
  bootdisk                  = "scsi0"
  disks {
    scsi {
      scsi0 {
        disk {
          discard = true
          emulatessd = true
          storage = "local-lvm"
          size = 40
        }
      }
    }
  }
  network {
    bridge = "vmbr0"
    model = "virtio"
    macaddr = var.ocp_infra02_mac
  }
}
