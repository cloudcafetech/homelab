resource "null_resource" "k8s-ad-ldap-integration" {
    depends_on = [
      null_resource.k8skube-master1-setup,
      null_resource.k8skube-master2-setup,
      null_resource.k8s-haproxy-lb-setup,
      proxmox_vm_qemu.k8skube-worker-1,
      proxmox_vm_qemu.k8skube-worker-2
    ]
    connection {
      type        = "ssh"
      user        = var.user
      host        = var.k8s_master01_ip
      private_key = file(var.privatekeypath)
    }
    provisioner "remote-exec" {
      inline = [
        "export lbpubip=${var.k8s_haproxy_lb}",
        "export lbpriip=${var.k8s_haproxy_lb}",
        "export ldapip=${var.ldapip}",
        "#export ldapip=${var.k8s_haproxy_lb}",
        "sh ./k8setup.sh adauth",
      ]
    }
}

resource "null_resource" "k8s-api-alter-master1" {
    depends_on = [ null_resource.k8s-ad-ldap-integration ]
    connection {
      type        = "ssh"
      user        = var.user
      host        = var.k8s_master01_ip
      private_key = file(var.privatekeypath)
    }
    provisioner "remote-exec" {
      inline = [
        "export lbpubip=${var.k8s_haproxy_lb}",
        "sh ./k8setup.sh apialter",
      ]
    }
}

resource "null_resource" "k8s-api-alter-master2" {
    depends_on = [ null_resource.k8s-ad-ldap-integration ]
    connection {
      type        = "ssh"
      user        = var.user
      host        = var.k8s_master02_ip
      private_key = file(var.privatekeypath)
    }
    provisioner "remote-exec" {
      inline = [
        "export lbpubip=${var.k8s_haproxy_lb}",
        "sh ./k8setup.sh apialter",
      ]
    }
}