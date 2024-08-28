resource "proxmox_vm_qemu" "k8s-haproxy-lb" {

  name                      = "k8s-haproxy-lb"
  target_node               = var.pve_node_name
  clone                     = "ubuntu-2204-template"
  os_type                   = "cloud-init"
  cpu                       = "host"
  agent                     = 1
  cores                     = 2
  memory                    = 2048
  ipconfig0                 = "ip=${var.k8s_haproxy_lb}/24,gw=${var.subnet_gw}"
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

resource "null_resource" "k8s-haproxy-lb-setup" {
    depends_on = [
     proxmox_vm_qemu.k8s-haproxy-lb
    ]
    connection {
      type        = "ssh"
      user        = "${var.user}"
      host        = "${var.k8s_haproxy_lb}"
      private_key = file(var.privatekeypath)
    }
    provisioner "file" {
      source      = "./k8setup.sh"
      destination = "k8setup.sh"
    }
    provisioner "file" {
      source      = "./haproxy.cfg"
      destination = "haproxy.cfg"
    }
    provisioner "remote-exec" {
      inline = [
        "chmod +x ./k8setup.sh",
        "sudo sh ./k8setup.sh lbsetup",
        "#curl -#OL https://raw.githubusercontent.com/cloudcafetech/k8s-terraform/master/kubeadm/haproxy.cfg",
        "sed -i -e 's:VMDNS1:k8skube-master-1:g' -e 's:VMDNS2:k8skube-master-2:g' -e 's:VMIP1:${var.k8s_master01_ip}:g' -e 's:VMIP2:${var.k8s_master02_ip}:g' haproxy.cfg",
        "sed -i '/VMDNS3/d' haproxy.cfg",
        "sudo mv haproxy.cfg /etc/haproxy/haproxy.cfg",
        "sudo chown root:root /etc/haproxy/haproxy.cfg",
        "sudo systemctl restart haproxy",
        "#sudo sh ./k8setup.sh ldapsetup",
      ]
    }
}
