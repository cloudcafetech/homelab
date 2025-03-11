#!/bin/bash

cd $(dirname ${BASH_SOURCE})

set -e

hub=${CLUSTER1:-hub}
c1=${CLUSTER1:-cluster1}
c2=${CLUSTER2:-cluster2}

hubctx="kind-${hub}"
c1ctx="kind-${c1}"
c2ctx="kind-${c2}"

# Issue related kernel limits such as number of open files, inotifiy watches, etc.
#sudo echo "fs.inotify.max_user_watches=524288" >> /etc/sysctl.conf
#sudo echo "fs.inotify.max_user_instances=8192" >> /etc/sysctl.conf
#sudo sysctl -p /etc/sysctl.conf 

kind create cluster --name "${hub}"
kind create cluster --name "${c1}"
kind create cluster --name "${c2}"

echo "Download and install clusteradm"
wget -qO- https://github.com/open-cluster-management-io/clusteradm/releases/latest/download/clusteradm_linux_amd64.tar.gz | sudo tar -xvz -C /usr/local/bin/
sudo chmod +x /usr/local/bin/clusteradm

echo "Initialize the ocm hub cluster\n"
clusteradm init --wait --context ${hubctx}
joincmd=$(clusteradm get token --context ${hubctx} | grep clusteradm)

echo "Join cluster1 to hub\n"
$(echo ${joincmd} --force-internal-endpoint-lookup --wait --context ${c1ctx} | sed "s/<cluster_name>/$c1/g")

echo "Join cluster2 to hub\n"
$(echo ${joincmd} --force-internal-endpoint-lookup --wait --context ${c2ctx} | sed "s/<cluster_name>/$c2/g")

echo "Accept join of cluster1 and cluster2"
clusteradm accept --context ${hubctx} --clusters ${c1},${c2} --wait

kubectl get managedclusters --all-namespaces --context ${hubctx}
