resource "proxmox_vm_qemu" "ocpworker1" {
  depends_on = [ proxmox_vm_qemu.ocpmaster1 ]

  name                      = var.ocpworker01_hn
  target_node               = var.pve_node_name
  vmid                      = var.ocp_worker01_ip
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
    macaddr = var.ocp_worker01_mac
  }
}

resource "proxmox_vm_qemu" "ocpworker2" {
  depends_on = [ proxmox_vm_qemu.ocpmaster1 ]

  name                      = var.ocpworker02_hn
  target_node               = var.pve_node_name
  vmid                      = var.ocp_worker02_ip
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
    macaddr = var.ocp_worker02_mac
  }
}
