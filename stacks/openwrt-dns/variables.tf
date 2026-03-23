variable "environment" {
  type        = string
  description = "Inventory environment name."
}

variable "inventory_root" {
  type        = string
  default     = "../../inventory"
  description = "Path from this stack to the inventory root."
}

variable "openwrt_hostname" {
  type        = string
  description = "OpenWrt LuCI hostname or IP."
}

variable "openwrt_port" {
  type        = number
  default     = 80
  description = "OpenWrt LuCI RPC port."
}

variable "openwrt_scheme" {
  type        = string
  default     = "http"
  description = "OpenWrt LuCI RPC scheme."
}

variable "openwrt_username" {
  type        = string
  default     = "root"
  description = "OpenWrt LuCI username."
}

variable "openwrt_password" {
  type        = string
  sensitive   = true
  description = "OpenWrt LuCI password."
}

variable "openwrt_firewall_enabled" {
  type        = bool
  default     = false
  description = "Whether to validate and reconcile aggregated firewall rules for Traefik-exposed services."
}

variable "openwrt_firewall_apply" {
  type        = bool
  default     = false
  description = "Whether to create, update and delete the derived OpenWrt firewall rules instead of failing on drift."
}

variable "openwrt_firewall_ssh_host" {
  type        = string
  default     = null
  nullable    = true
  description = "Optional SSH host override used by the firewall reconciler when applying managed OpenWrt rules."
}

variable "openwrt_firewall_ssh_port" {
  type        = number
  default     = 22
  description = "SSH port used by the firewall reconciler when applying managed OpenWrt rules."
}

variable "openwrt_firewall_ssh_user" {
  type        = string
  default     = "root"
  description = "SSH user used by the firewall reconciler when applying managed OpenWrt rules."
}

variable "proxmox_api_url" {
  type        = string
  default     = null
  nullable    = true
  description = "Optional Proxmox API URL used to resolve CT runtime IPs for firewall rules."
}

variable "proxmox_api_token_id" {
  type        = string
  default     = null
  nullable    = true
  description = "Optional Proxmox API token ID used to resolve CT runtime IPs for firewall rules."
}

variable "proxmox_api_token" {
  type        = string
  default     = null
  nullable    = true
  sensitive   = true
  description = "Optional Proxmox API token secret used to resolve CT runtime IPs for firewall rules."
}

variable "proxmox_tls_insecure" {
  type        = bool
  default     = true
  description = "Disable TLS verification for Proxmox API requests used by firewall reconciliation."
}
