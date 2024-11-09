## Delete node from Proxmox cluster

- Stop the corosync and pve-cluster services on the node

```systemctl stop pve-cluster corosync```

- Start the cluster file system again in local mode

```pmxcfs -l```

- Delete the corosync configuration files

```rm /etc/pve/corosync.conf; rm -r /etc/corosync/*```

- You can now start the file system again as a normal service

```killall pmxcfs; systemctl start pve-cluster```

- Delete Node from cluster 

```pvecm delnode oldnode```

- If the command fails due to a loss of quorum in the remaining node, you can set the expected votes to 1 as a workaround

```pvecm expected 1```

- And then repeat the pvecm delnode command

```pvecm delnode oldnode```

- login separated node and delete all the remaining cluster files on it so later node can be added to another cluster again without problems

```rm /var/lib/corosync/* ```
