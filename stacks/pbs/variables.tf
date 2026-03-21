variable "targets" {
  type = map(object({
    kind          = string
    vmid          = number
    node          = string
    tags          = list(string)
    backup_policy = any
  }))
  default     = {}
  description = "Backup candidates exported by proxmox-base."
}
