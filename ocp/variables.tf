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

variable "jumphost" {
  type        = string
  description = "IP address of Jumphost"
  default = "192.168.29.214"
}

variable "ocp_jump_ip" {
  type        = string
  description = "IP address of ocp bootstrap"
  default = "214"
}

variable "ocp_jump2_ip" {
  type        = string
  description = "Secondary IP address of jumphost"
  default = "215"
}

variable "jio_gw" {
  type        = string
  description = "IP address of gateway"
  default = "192.168.29.1"
}

variable "pull_secret" {
  type        = string
  description = "IP address of gateway"
  default = "./pull-secret"
}

variable "ocp_subnet" {
  type        = string
  description = "Subnet of NW"
  default = "192.168.29"
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

variable "ocp_bootstrap_mac" {
  type        = string
  description = "MAC address of ocp bootstrap"
  default = "BC:24:11:11:22:88"
}

variable "ocp_master01_mac" {
  type        = string
  description = "MAC address of ocp master 01"
  default = "BC:24:11:11:22:11"
}

variable "ocp_master02_mac" {
  type        = string
  description = "MAC address of ocp master 02"
  default = "BC:24:11:11:22:22"
}

variable "ocp_master03_mac" {
  type        = string
  description = "MAC address of ocp master 03"
  default = "BC:24:11:11:22:33"
}

variable "ocp_infra01_mac" {
  type        = string
  description = "MAC address of ocp infra 01"
  default = "BC:24:11:11:22:44"
}

variable "ocp_infra02_mac" {
  type        = string
  description = "MAC address of ocp infra 02"
  default = "BC:24:11:11:22:55"
}

variable "ocp_worker01_mac" {
  type        = string
  description = "MAC address of ocp worker 01"
  default = "BC:24:11:11:22:66"
}

variable "ocp_worker02_mac" {
  type        = string
  description = "MAC address of ocp worker 02"
  default = "BC:24:11:11:22:77"
}

variable "ocp_bootstrap_ip" {
  type        = string
  description = "IP address of ocp bootstrap"
  default = "216"
}

variable "ocp_master01_ip" {
  type        = string
  description = "IP address of ocp master 01"
  default = "217"
}

variable "ocp_master02_ip" {
  type        = string
  description = "IP address of ocp master 02"
  default = "218"
}

variable "ocp_master03_ip" {
  type        = string
  description = "IP address of ocp master 03"
  default = "219"
}

variable "ocp_infra01_ip" {
  type        = string
  description = "IP address of ocp infra 01"
  default = "220"
}

variable "ocp_infra02_ip" {
  type        = string
  description = "IP address of ocp infra 02"
  default = "221"
}

variable "ocp_worker01_ip" {
  type        = string
  description = "IP address of ocp worker 01"
  default = "222"
}

variable "ocp_worker02_ip" {
  type        = string
  description = "IP address of ocp worker 02"
  default = "223"
}

variable "bootstrap_hn" {
  type        = string
  description = "Hostname of ocp bootstrap"
  default = "bootstrap"
}

variable "ocpmaster01_hn" {
  type        = string
  description = "Hostname of ocp master 01"
  default = "ocpmaster1"
}

variable "ocpmaster02_hn" {
  type        = string
  description = "Hostname of ocp master 02"
  default = "ocpmaster2"
}

variable "ocpmaster03_hn" {
  type        = string
  description = "Hostname of ocp master 03"
  default = "ocpmaster3"
}

variable "ocpinfra01_hn" {
  type        = string
  description = "Hostname of ocp infra 01"
  default = "ocpinfra01"
}

variable "ocpinfra02_hn" {
  type        = string
  description = "Hostname of ocp infra 02"
  default = "ocpinfra02"
}

variable "ocpworker01_hn" {
  type        = string
  description = "Hostname of ocp worker 01"
  default = "ocpworker01"
}

variable "ocpworker02_hn" {
  type        = string
  description = "Hostname of ocp worker 02"
  default = "ocpworker02"
}
