provider "proxmox" {
  endpoint = var.proxmox_api_url
  username = "root@pam"
  password = var.proxmox_password
  insecure = var.proxmox_tls_insecure
}
