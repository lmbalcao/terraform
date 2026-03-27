variable "target_node" {
  type        = string
  description = "Target Proxmox node name."
}

variable "hostname" {
  type        = string
  description = "Container hostname."
}

variable "vmid" {
  type        = number
  description = "Explicit VMID for the container."
}

variable "tags" {
  type        = list(string)
  default     = []
  description = "Workload tags."
}

variable "description" {
  type        = string
  default     = null
  nullable    = true
  description = "Optional CT description written to Proxmox notes."
}

variable "ostemplate" {
  type        = string
  description = "Resolved LXC template path."
}

variable "root_password" {
  type        = string
  sensitive   = true
  description = "Bootstrap root password."
}

variable "unprivileged" {
  type        = bool
  default     = true
  description = "Whether to create the CT as unprivileged."
}

variable "cores" {
  type        = number
  description = "CPU cores."
}

variable "memory_mb" {
  type        = number
  description = "Memory in MB."
}

variable "swap_mb" {
  type        = number
  default     = 0
  description = "Swap in MB."
}

variable "on_boot" {
  type        = bool
  description = "Start on node boot."
}

variable "start" {
  type        = bool
  description = "Start immediately after creation."
}

variable "ssh_public_keys" {
  type        = list(string)
  default     = []
  description = "SSH public keys injected in the CT."
}

variable "nameserver" {
  type        = string
  default     = null
  nullable    = true
  description = "Primary nameserver."
}

variable "searchdomain" {
  type        = string
  default     = null
  nullable    = true
  description = "DNS search domain."
}

variable "rootfs_storage" {
  type        = string
  description = "Root filesystem storage."
}

variable "rootfs_size_gb" {
  type        = number
  description = "Root filesystem size in GB."
}

variable "network_bridge" {
  type        = string
  description = "Bridge name."
}

variable "network_tag" {
  type        = number
  default     = null
  nullable    = true
  description = "Optional VLAN tag. Use null or 0 for untagged access bridges."
}

variable "network_mode" {
  type        = string
  description = "Network mode: static or dhcp."
}

variable "network_ip_cidr" {
  type        = string
  default     = null
  nullable    = true
  description = "Static IP in CIDR format."
}

variable "network_gateway" {
  type        = string
  default     = null
  nullable    = true
  description = "Static gateway."
}
