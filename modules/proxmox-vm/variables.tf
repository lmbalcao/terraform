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

variable "start_at_node_boot" {
  type        = bool
  description = "Start VM on node boot."
}

variable "vm_state" {
  type        = string
  description = "Desired VM state."
}

variable "network_bridge" {
  type        = string
  description = "Bridge name."
}

variable "network_tag" {
  type        = number
  description = "VLAN tag."
}

variable "network_address" {
  type        = string
  default     = null
  nullable    = true
  description = "Desired guest address metadata."
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
  type        = string
  default     = null
  nullable    = true
  description = "Optional Proxmox clone source."
}
