provider "proxmox" {
  pm_api_url      = "${trimsuffix(var.proxmox_api_url, "/")}api2/json"
  pm_user         = "root@pam"
  pm_password     = var.proxmox_password
  pm_tls_insecure = var.proxmox_tls_insecure
}
