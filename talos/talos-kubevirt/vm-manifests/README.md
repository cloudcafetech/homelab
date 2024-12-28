## VM Manifests

### Ubuntu 2204 (Using multus cni)

- Image pull ( ```kubectl create -f import-dv-ubuntu.yml``` )

- Create VM Disks ( ```kubectl create -f ubuntu-external-dv-pvc.yaml``` )

- Deploy VM ( ```kubectl create -f ubuntu-external-vm.yaml``` )

### Debian 12 Webserver (Using POD network)

- Image pull ( ```kubectl create -f import-dv-debian.yml``` )

- Create VM Disks ( ```kubectl create -f debian-dv-pvc.yaml``` )

- Deploy VM ( ```kubectl create -f debian-webserver-vm.yaml``` )

### Fedora 40 (Using POD network)

- Image pull ( ```kubectl create -f import-dv-fedora.yml``` )

- Create VM Disks ( ```kubectl create -f fedora-dv-pvc.yaml``` )

- Deploy VM ( ```kubectl create -f fedora-vm.yaml``` )

### Windows 2022 

This is a Kubevirt Virtual Machine Manifest that i used to test out server2022 on my KubeVirt cluster.

To make this to work you first have to download a evaluation ISO from Microsoft. After that, you have to upload the iso to Kubevirt by using the `virtctl` command. And before uploading, make sure to to a port-forward to the cdi-proxy to upload the ISO.

- Create the port-forward to the cdi-proxy ( ```kubectl port-forward -n cdi svc/cdi-uploadproxy 8443:443``` )

- Open a new terminal and upload the ISO ( ```kubectl virt image-upload pvc win2022-iso --size=6Gi  --access-mode=ReadWriteMany --storage-class=nfs-client-zimaboard --image-path <path-to-your-iso.iso> --uploadproxy-url https://localhost:8443 --insecure``` )

- Deploy VM ( ```kubectl create -f windows-2022-vm.yaml``` )

- Connect to the VNC console with ( ```kubectl virt console server2022``` )

- Install your Windows server 2022.
