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
