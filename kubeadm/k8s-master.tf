resource "proxmox_vm_qemu" "k8skube-master-1" {

  name                      = "k8skube-master-1"
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

resource "proxmox_vm_qemu" "k8skube-master-2" {

  name                      = "k8skube-master-2"
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

resource "null_resource" "k8skube-master1-setup" {
    depends_on = [
     proxmox_vm_qemu.k8skube-master-1,
     proxmox_vm_qemu.k8skube-master-2,
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
        "chmod +x ./k8setup.sh",
        "sudo sh ./k8setup.sh k8scommon",
        "sudo kubeadm init --token=hp9b0k.1g9tqz8vkf78ucwf --pod-network-cidr=10.244.0.0/16 --control-plane-endpoint '${var.k8s_haproxy_lb}:6443' --upload-certs --ignore-preflight-errors=all | grep -Ei 'kubeadm join|discovery-token-ca-cert-hash|certificate-key' 2>&1 | tee kubeadm-output.txt",
        "sudo sh ./k8setup.sh master",
        "sudo chown -R cloudcafe:cloudcafe ~/.kube",
        "echo 'export KUBECONFIG=/home/cloudcafe/.kube/config' >> $HOME/.bash_profile",
      ]
    }
    provisioner "local-exec" {
      command = "ansible-playbook -i '${var.k8s_master01_ip},' playbook.yml"
    }
}

resource "null_resource" "k8skube-master2-setup" {
  depends_on = [null_resource.k8skube-master1-setup]
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
    provisioner "file" {
      source      = "./kubeadm-output.txt"
      destination = "kubeadm-output.txt"
    }
    provisioner "remote-exec" {
      inline = [
        "chmod +x ./k8setup.sh",
        "sudo sh ./k8setup.sh k8scommon",
        "more kubeadm-output.txt | grep certificate-key | sed -n 's/--control-plane --certificate-key//p' > CERTKEY",
        "more kubeadm-output.txt | grep discovery-token-ca-cert-hash | tail -1 | sed -n 's/--discovery-token-ca-cert-hash//p' > HASHKEY",
        "sudo kubeadm join '${var.k8s_haproxy_lb}:6443' --token=hp9b0k.1g9tqz8vkf78ucwf --discovery-token-ca-cert-hash $(cat HASHKEY) --control-plane --certificate-key $(cat CERTKEY) --ignore-preflight-errors=all",
        "sudo sh ./k8setup.sh master",
        "sudo chown -R cloudcafe:cloudcafe ~/.kube",
        "echo 'export KUBECONFIG=/home/cloudcafe/.kube/config' >> $HOME/.bash_profile",
      ]
    }
}