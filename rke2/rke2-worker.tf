resource "proxmox_vm_qemu" "k8srke2-worker-1" {
  depends_on = [
    null_resource.k8srke2-master1-setup,
    null_resource.k8srke2-master2-setup
  ]

  name                      = "k8srke2-worker-1"
  target_node               = var.pve_node_name
  clone                     = "ubuntu-2204-template"
  os_type                   = "cloud-init"
  cpu                       = "host"  
  agent                     = 1
  cores                     = 3
  memory                    = 3072
  ipconfig0                 = "ip=${var.k8s_worker01_ip}/24,gw=${var.subnet_gw}"
  onboot                    = true
  scsihw                    = "virtio-scsi-pci"
  bootdisk                  = "scsi0"
  cloudinit_cdrom_storage   = "local-lvm"
  disks {
        scsi {
            scsi0 {
                disk {
                  storage = "local-lvm"
                  size = 40
                }
            }
        }
  }
  connection {
    type        = "ssh"
    user        = var.user
    host        = var.k8s_worker01_ip
    private_key = file(var.privatekeypath)
  }
  provisioner "file" {
    source      = "./k8setup.sh"
    destination = "./k8setup.sh"
  }
  provisioner "remote-exec" {
    inline = [
      "sudo mkdir -p /etc/rancher/rke2/",
      "echo 'server: https://${var.k8s_master01_ip}:9345\ntoken: ksrkePK\nnode-label:\n- region=worker\n' > config.yaml",
      "sudo mv config.yaml /etc/rancher/rke2/config.yaml",
      "sudo chown root:root /etc/rancher/rke2/config.yaml",
      "chmod +x ./k8setup.sh",
      "sudo sh ./k8setup.sh worker",    ]
  }
}

resource "proxmox_vm_qemu" "k8srke2-worker-2" {
  depends_on = [
    null_resource.k8srke2-master1-setup,
    null_resource.k8srke2-master2-setup
  ]

  name                      = "k8srke2-worker-2"
  target_node               = var.pve_node_name
  clone                     = "ubuntu-2204-template"
  os_type                   = "cloud-init"
  cpu                       = "host"  
  agent                     = 1
  cores                     = 3
  memory                    = 3072
  ipconfig0                 = "ip=${var.k8s_worker02_ip}/24,gw=${var.subnet_gw}"
  onboot                    = true
  scsihw                    = "virtio-scsi-pci"
  bootdisk                  = "scsi0"
  cloudinit_cdrom_storage   = "local-lvm"
  disks {
        scsi {
            scsi0 {
                disk {
                  storage = "local-lvm"
                  size = 40
                }
            }
        }
  }
  connection {
    type        = "ssh"
    user        = var.user
    host        = var.k8s_worker02_ip
    private_key = file(var.privatekeypath)
  }
  provisioner "file" {
    source      = "./k8setup.sh"
    destination = "./k8setup.sh"
  }
  provisioner "remote-exec" {
    inline = [
      "sudo mkdir -p /etc/rancher/rke2/",
      "echo 'server: https://${var.k8s_master01_ip}:9345\ntoken: ksrkePK\nnode-label:\n- region=worker\n' > config.yaml",
      "sudo mv config.yaml /etc/rancher/rke2/config.yaml",
      "sudo chown root:root /etc/rancher/rke2/config.yaml",
      "chmod +x ./k8setup.sh",
      "sudo sh ./k8setup.sh worker",    ]
  }
}
