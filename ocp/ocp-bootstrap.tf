resource "proxmox_vm_qemu" "bootstrap" {
  depends_on = [ jumphost ]

  name                      = "var.bootstrap_hn"
  target_node               = var.pve_node_name
  vmid                      = var.ocp_bootstrap_ip
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
    macaddr = var.ocp_bootstrap_mac
  }
}
