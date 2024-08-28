resource "proxmox_vm_qemu" "k8srke2-master-1" {

  name                      = "k8srke2-master-1"
  target_node               = var.pve_node_name
  clone                     = "ubuntu-2204-template"
  os_type                   = "cloud-init"
  cpu                       = "host"
  agent                     = 1
  cores                     = 3
  memory                    = 4028
  ipconfig0                 = "ip=${var.k8s_master01_ip}/24,gw=${var.subnet_gw}"
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
}

resource "proxmox_vm_qemu" "k8srke2-master-2" {

  name                      = "k8srke2-master-2"
  target_node               = var.pve_node_name
  clone                     = "ubuntu-2204-template"
  os_type                   = "cloud-init"
  cpu                       = "host"
  agent                     = 1
  cores                     = 3
  memory                    = 4028
  ipconfig0                 = "ip=${var.k8s_master02_ip}/24,gw=${var.subnet_gw}"
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
}

resource "null_resource" "k8srke2-master1-setup" {
    depends_on = [
     proxmox_vm_qemu.k8srke2-master-1,
     proxmox_vm_qemu.k8srke2-master-2,
     proxmox_vm_qemu.k8s-haproxy-lb,
     null_resource.k8s-haproxy-lb-setup
    ]
    connection {
      type        = "ssh"
      user        = var.user
      host        = var.k8s_master01_ip
      private_key = file(var.privatekeypath)
    }
    provisioner "file" {
      source      = "./k8setup.sh"
      destination = "k8setup.sh"
    }
    provisioner "remote-exec" {
      inline = [
        "sudo mkdir -p /etc/rancher/rke2/",
        "echo 'token: ksrkePK\nwrite-kubeconfig-mode: 0644\ncluster-cidr: 192.168.0.0/16\nservice-cidr: 192.167.0.0/16\nnode-label:\n- region=master\ntls-san:\n  - ${var.k8s_master01_ip}\n  - ${var.k8s_master02_ip}\n  - ${var.k8s_haproxy_lb}\n  - k8s-haproxy-lb\n  - k8srke2-master-1\n  - k8srke2-master-2\ndisable:\n  - rke2-snapshot-controller\n  - rke2-snapshot-controller-crd\n  - rke2-snapshot-validation-webhook\n' > config.yaml",
        "sudo mv config.yaml /etc/rancher/rke2/config.yaml",
        "sudo chown root:root /etc/rancher/rke2/config.yaml",
        "chmod +x ./k8setup.sh",
        "sudo sh ./k8setup.sh master",
        "sudo chown -R cloudcafe:cloudcafe ~/.kube",
        "echo 'export PATH=/var/lib/rancher/rke2/bin:$PATH' >> $HOME/.bash_profile",
        "echo 'export KUBECONFIG=/home/cloudcafe/.kube/config' >> $HOME/.bash_profile",
      ]
    }
    provisioner "local-exec" {
      command = "ansible-playbook -i '${var.k8s_master01_ip},' playbook.yml"
    }
}

resource "null_resource" "k8srke2-master2-setup" {
  depends_on = [null_resource.k8srke2-master1-setup]
    connection {
      type        = "ssh"
      user        = var.user
      host        = var.k8s_master02_ip
      private_key = file(var.privatekeypath)
    }
    provisioner "file" {
      source      = "./k8setup.sh"
      destination = "k8setup.sh"
    }
    provisioner "remote-exec" {
      inline = [
        "sudo mkdir -p /etc/rancher/rke2/",
        "echo 'server: https://${var.k8s_master01_ip}:9345\ntoken: ksrkePK\nwrite-kubeconfig-mode: 0644\ncluster-cidr: 192.168.0.0/16\nservice-cidr: 192.167.0.0/16\nnode-label:\n- region=master\ntls-san:\n  - ${var.k8s_master01_ip}\n  - ${var.k8s_master02_ip}\n  - ${var.k8s_haproxy_lb}\n  - k8s-haproxy-lb\n  - k8srke2-master-1\n  - k8srke2-master-2\n' > config.yaml",
        "sudo mv config.yaml /etc/rancher/rke2/config.yaml",
        "sudo chown root:root /etc/rancher/rke2/config.yaml",
        "chmod +x ./k8setup.sh",
        "sudo sh ./k8setup.sh master",
        "sudo chown -R cloudcafe:cloudcafe ~/.kube",
        "echo 'export PATH=/var/lib/rancher/rke2/bin:$PATH' >> $HOME/.bash_profile",
        "echo 'export KUBECONFIG=/home/cloudcafe/.kube/config' >> $HOME/.bash_profile",
      ]
    }
}
