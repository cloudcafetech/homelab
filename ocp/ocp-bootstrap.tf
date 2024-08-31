resource "proxmox_vm_qemu" "bootstrap" {
  depends_on = [ proxmox_vm_qemu.jumphost ]

  name                      = var.bootstrap_hn
  target_node               = var.pve_node_name
  vmid                      = var.ocp_bootstrap_ip
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
    macaddr = var.ocp_bootstrap_mac
  }
}
