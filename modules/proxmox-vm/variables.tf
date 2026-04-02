variable "target_node" {
  type        = string
  description = "Target Proxmox node name."
}

variable "name" {
  type        = string
  description = "VM name."
}

variable "vmid" {
  type        = number
  description = "Explicit VMID for the VM."
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
  description = "Optional VM description written to Proxmox notes."
}

variable "cpu_cores" {
  type        = number
  description = "CPU cores."
}

variable "cpu_sockets" {
  type        = number
  default     = 1
  description = "CPU sockets."
}

variable "memory_mb" {
  type        = number
  description = "Memory in MB."
}

variable "ci_user" {
  type        = string
  default     = "root"
  description = "Cloud-init user configured for the guest."
}

variable "scsi_hardware" {
  type        = string
  default     = "virtio-scsi-single"
  description = "SCSI controller model."
}

variable "start_at_node_boot" {
  type        = bool
  description = "Start VM on node boot."
}

variable "vm_state" {
  type        = string
  description = "Desired VM state: running or stopped."
}

variable "network_bridge" {
  type        = string
  description = "Bridge name."
}

variable "network_tag" {
  type        = number
  default     = null
  nullable    = true
  description = "Optional VLAN tag."
}

variable "network_address" {
  type        = string
  default     = null
  nullable    = true
  description = "Desired guest address metadata."
}

variable "network_gateway" {
  type        = string
  default     = null
  nullable    = true
  description = "Desired guest gateway metadata."
}

variable "network_mode" {
  type        = string
  description = "Network mode: static or dhcp."
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
  description = "Root disk storage."
}

variable "rootfs_size_gb" {
  type        = number
  description = "Root disk size in GB."
}

variable "source_clone" {
  type        = number
  default     = null
  nullable    = true
  description = "Optional Proxmox VM ID to clone from."
}
