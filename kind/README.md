## Multi Cluster Management [MCO](https://github.com/open-cluster-management-io/ocm) 

Welcome! The open-cluster-management.io project is focused on enabling end-to-end visibility and control across your Kubernetes clusters.

The Open Cluster Management (OCM) architecture uses a hub - agent model. The hub centralizes control of all the managed clusters. An agent, which we call the klusterlet, resides on each managed cluster to manage registration to the hub and run instructions from the hub.

## K8s DR [Ramen](https://github.com/RamenDR/ramen)
Ramen is an open-cluster-management (OCM) placement extension that provides recovery and relocation services for workloads, and their persistent data, across a set of OCM managed clusters. Ramen provides cloud-native interfaces to orchestrate the placement of workloads and their data on PersistentVolumes, which include:

Relocating workloads to a peer cluster, for planned migrations across clusters
Recovering workloads to a peer cluster, due to unplanned loss of a cluster
Ramen relies on storage plugins providing support for the CSI storage replication addon, of which ceph-csi is a sample implementation.

- [Install](https://github.com/RamenDR/ramen/blob/main/docs/install.md)
