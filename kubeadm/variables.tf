variable "proxmox_host_ip" {
  type        = string
  description = "IP address of your Proxmox host"
  default     = "192.168.29.112"
}

variable "pve_node_name" {
  type        = string
  description = "Name of your PVE node name (ex: pve)"
  default     = "pve"
}

variable "machine_type" {
  type        = string
  description = "The machine type to deploy to"
  default     = "e2-medium"
}

variable "image" {
  type        = map(string)
  description = "The image to deploy to"
  default     = {
     centos   = "projects/centos-cloud/global/images/centos-stream-8-v20240110"
     ubuntu   = "projects/ubuntu-os-cloud/global/images/ubuntu-2004-focal-v20240209"
  }
}

variable "user" {
  type    = string
  default = "cloudcafe"
}

variable "email" {
  type    = string
  default = "test@gmail.com"
}

variable "privatekeypath" {
  type    = string
  default = "./gcpkey"
}

variable "publickeypath" {
  type    = string
  default = "./gcpkey.pub"
}

variable "ldapip" {
  type    = string
  description = "IP address of LDAP Server"
  default = "192.168.29.201"
}

variable "k8s_haproxy_lb" {
  type        = string
  description = "IP address of HAPROXY Load Balancer"
  default = "192.168.29.202"
}

variable "k8s_master01_ip" {
  type        = string
  description = "IP address of k8s master 01"
  default = "192.168.29.207"
}

variable "k8s_master02_ip" {
  type        = string
  description = "IP address of k8s master 02"
  default = "192.168.29.208"
}

variable "k8s_master03_ip" {
  type        = string
  description = "IP address of k8s master 03"
  default = "192.168.29.209"
}

variable "k8s_worker01_ip" {
  type        = string
  description = "IP address of k8s worker 01"
  default = "192.168.29.217"
}

variable "k8s_worker02_ip" {
  type        = string
  description = "IP address of k8s worker 02"
  default = "192.168.29.218"
}

variable "k8s_worker03_ip" {
  type        = string
  description = "IP address of k8s worker 03"
  default = "192.168.29.219"
}

variable "storage_pool_name" {
  type        = string
  description = "Name of the storage pool you want to use to store the VM disk"
}

variable "subnet_gw" {
  type        = string
  description = "IP address of gateway"
  default = "192.168.29.1"
}


