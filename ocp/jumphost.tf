resource "proxmox_vm_qemu" "jumphost" {

  name                      = "jumphost"
  target_node               = var.pve_node_name
  clone                     = "centos-8-template"
  os_type                   = "cloud-init"
  cpu                       = "host"
  agent                     = 1
  cores                     = 2
  memory                    = 2048
  ipconfig0                 = "ip=${var.jumphost}/24,gw=${var.jio_gw}"
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

resource "null_resource" "jumphost-setup" {
    depends_on = [
     proxmox_vm_qemu.jumphost
    ]
    connection {
      type        = "ssh"
      user        = "${var.user}"
      host        = "${var.jumphost}"
      private_key = file(var.privatekeypath)
    }
    provisioner "file" {
      source      = "./jumphost.sh"
      destination = "jumphost.sh"
    }
    provisioner "remote-exec" {
      inline = [
        "export jio_gw=${var.jio_gw}",
        "export pull_secret=${var.pull_secret}",
        "export ocp_bootstrap_mac=${var.ocp_bootstrap_mac}",
        "export ocp_master01_mac=${var.ocp_master01_mac}",
        "export ocp_master02_mac=${var.ocp_master02_mac}",
        "export ocp_master03_mac=${var.ocp_master03_mac}",
        "export ocp_infra01_mac=${var.ocp_infra01_mac}",
        "export ocp_infra02_mac=${var.ocp_infra02_mac}",
        "export ocp_worker01_mac=${var.ocp_worker01_mac}",
        "export ocp_worker02_mac=${var.ocp_worker02_mac}",
        "export ocp_bootstrap_ip=${var.ocp_bootstrap_ip}",
        "export ocp_master01_ip=${var.ocp_master01_ip}",
        "export ocp_master02_ip=${var.ocp_master02_ip}",
        "export ocp_master03_ip=${var.ocp_master03_ip}",
        "export ocp_infra01_ip=${var.ocp_infra01_ip}",
        "export ocp_infra02_ip=${var.ocp_infra02_ip}",
        "export ocp_worker01_ip=${var.ocp_worker01_ip}",
        "export ocp_worker02_ip=${var.ocp_worker02_ip}",
        "export bootstrap_hn=${var.bootstrap_hn}",
        "export ocpmaster01_hn=${var.ocpmaster01_hn}",
        "export ocpmaster02_hn=${var.ocpmaster02_hn}",
        "export ocpmaster03_hn=${var.ocpmaster03_hn}",
        "export ocpinfra01_hn=${var.ocpinfra01_hn}",
        "export ocpinfra02_hn=${var.ocpinfra02_hn}",
        "export ocpworker01_hn=${var.ocpworker01_hn}",
        "export ocpworker02_hn=${var.ocpworker02_hn}",
        "chmod +x ./jumphost.sh",
        "sudo sh ./jumphost.sh setupall"
      ]
    }
}
