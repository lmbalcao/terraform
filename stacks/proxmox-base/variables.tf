variable "environment" {
  type        = string
  description = "Inventory environment name."
}

variable "inventory_root" {
  type        = string
  default     = "../../inventory"
  description = "Path from this stack to the inventory root."
}

variable "proxmox_api_url" {
  type        = string
  description = "Proxmox API URL."
}

variable "proxmox_api_token_id" {
  type        = string
  description = "Proxmox API token ID."
}

variable "proxmox_api_token" {
  type        = string
  sensitive   = true
  description = "Proxmox API token secret."
}

variable "root_password" {
  type        = string
  sensitive   = true
  description = "Bootstrap root password for CTs."
}

variable "ssh_public_keys" {
  type        = list(string)
  default     = []
  description = "SSH public keys injected in CTs."
}

variable "default_search_domain" {
  type        = string
  default     = null
  nullable    = true
  description = "Fallback DNS search domain."
}

variable "default_lxc_template" {
  type        = string
  default     = null
  nullable    = true
  description = "Fallback LXC template if inventory does not define one."
}

variable "network_bridge" {
  type        = string
  default     = "vmbr0"
  description = "Fallback bridge name."
}
