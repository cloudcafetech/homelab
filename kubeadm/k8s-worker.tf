resource "proxmox_vm_qemu" "k8skube-worker-1" {
  depends_on = [
    null_resource.k8skube-master1-setup,
    null_resource.k8skube-master2-setup
  ]

  name                      = "k8skube-worker-1"
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
  provisioner "file" {
    source      = "./kubeadm-output.txt"
    destination = "kubeadm-output.txt"
  }
  provisioner "remote-exec" {
    inline = [
      "chmod +x ./k8setup.sh",
      "sudo sh ./k8setup.sh k8scommon",
      "more kubeadm-output.txt | grep discovery-token-ca-cert-hash | tail -1 | sed -n 's/--discovery-token-ca-cert-hash//p' > HASHKEY",
      "sudo kubeadm join '${var.k8s_haproxy_lb}:6443' --token hp9b0k.1g9tqz8vkf78ucwf --discovery-token-ca-cert-hash $(cat HASHKEY) --ignore-preflight-errors=all",
    ]
  }
}

resource "proxmox_vm_qemu" "k8skube-worker-2" {
  depends_on = [
    null_resource.k8skube-master1-setup,
    null_resource.k8skube-master2-setup
  ]

  name                      = "k8skube-worker-2"
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
  provisioner "file" {
    source      = "./kubeadm-output.txt"
    destination = "kubeadm-output.txt"
  }
  provisioner "remote-exec" {
    inline = [
      "chmod +x ./k8setup.sh",
      "sudo sh ./k8setup.sh k8scommon",
      "more kubeadm-output.txt | grep discovery-token-ca-cert-hash | tail -1 | sed -n 's/--discovery-token-ca-cert-hash//p' > HASHKEY",
      "sudo kubeadm join '${var.k8s_haproxy_lb}:6443' --token hp9b0k.1g9tqz8vkf78ucwf --discovery-token-ca-cert-hash $(cat HASHKEY) --ignore-preflight-errors=all",
    ]
  }
}
