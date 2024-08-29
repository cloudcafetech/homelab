terraform {
  required_providers {
    proxmox = {
      source  = "telmate/proxmox"
      version = "3.0.1-rc3"
    }
  }
}

provider "proxmox" {
  pm_api_url   = "https://${var.proxmox_host_ip}:8006/api2/json"
  pm_api_token_id      = "root@pam!terraform"
  pm_api_token_secret  = "32b2f8c4-e920-4d17-911b-eb80aa0e822a"
  pm_tls_insecure = true
}
