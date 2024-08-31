resource "proxmox_vm_qemu" "ocpmaster1" {
  depends_on = [ proxmox_vm_qemu.bootstrap ]

  name                      = var.ocpmaster01_hn
  target_node               = var.pve_node_name
  vmid                      = var.ocp_master01_ip
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
    macaddr = var.ocp_master01_mac
  }
}

resource "proxmox_vm_qemu" "ocpmaster2" {
  depends_on = [ proxmox_vm_qemu.bootstrap ]

  name                      = var.ocpmaster02_hn
  target_node               = var.pve_node_name
  vmid                      = var.ocp_master02_ip
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
    macaddr = var.ocp_master02_mac
  }
}

resource "proxmox_vm_qemu" "ocpmaster3" {
  depends_on = [ proxmox_vm_qemu.bootstrap ]

  name                      = var.ocpmaster03_hn
  target_node               = var.pve_node_name
  vmid                      = var.ocp_master03_ip
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
    macaddr = var.ocp_master03_mac
  }
}
