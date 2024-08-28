resource "null_resource" "k8s-ecosystem-setup" {
    depends_on = [
      null_resource.k8srke2-master1-setup,
      null_resource.k8srke2-master2-setup,
      null_resource.k8s-haproxy-lb-setup
    ]
    connection {
      type        = "ssh"
      user        = var.user
      host        = var.k8s_master01_ip
      private_key = file(var.privatekeypath)
    }
    provisioner "remote-exec" {
      inline = [
        "curl -#OL https://raw.githubusercontent.com/cloudcafetech/k8s-terraform/master/all-ing.yaml",
        "sed -i 's:34.125.24.130:${var.k8s_haproxy_lb}:g' all-ing.yaml",
        "sed -i 's:1.2.3.4:${var.k8s_haproxy_lb}:g' all-ing.yaml",
        "sh ./k8setup.sh k8secoa",
      ]
    }
    provisioner "local-exec" {
      command = "ansible-playbook -i '${var.k8s_master01_ip},' playbook.yml"
    }
}
