resource "null_resource" "k8s-ecosystem-setup" {
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
        "kubectl label nodes k8skube-master-1 region=master",
        "kubectl label nodes k8skube-master-2 region=master",
        "kubectl taint nodes k8skube-master-1 node-role.kubernetes.io/control-plane-",
        "kubectl taint nodes k8skube-master-2 node-role.kubernetes.io/control-plane-",
        "curl -#OL https://raw.githubusercontent.com/cloudcafetech/k8s-terraform/master/all-ing.yaml",
        "sed -i 's:34.125.24.130:${var.k8s_haproxy_lb}:g' all-ing.yaml",
        "sed -i 's:1.2.3.4:${var.k8s_haproxy_lb}:g' all-ing.yaml",
        "sh ./k8setup.sh k8secoa",
      ]
    }
}