###############################################################################
# Proxmox Provider
###############################################################################

variable "proxmox_api_url" {
  type        = string
  description = "URL da API do Proxmox (ex: https://pve:8006/api2/json)"
}

variable "proxmox_api_token_id" {
  type        = string
  description = "Token ID do Proxmox (ex: terraform@pve!token)"
}

variable "proxmox_api_token" {
  type        = string
  sensitive   = true
  description = "Token secreto da API do Proxmox"
}

