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
  description = "Whether to validate and reconcile firewall rules for Traefik-exposed services."
}

variable "openwrt_firewall_apply" {
  type        = bool
  default     = false
  description = "Whether to append missing ports to the first compatible OpenWrt firewall rule."
}

variable "openwrt_firewall_ssh_host" {
  type        = string
  default     = null
  nullable    = true
  description = "OpenWrt SSH host for firewall checks. Defaults to openwrt_hostname."
}

variable "openwrt_firewall_ssh_port" {
  type        = number
  default     = 22
  description = "OpenWrt SSH port used by the firewall check script."
}

variable "openwrt_firewall_ssh_user" {
  type        = string
  default     = "root"
  description = "OpenWrt SSH user used by the firewall check script."
}
