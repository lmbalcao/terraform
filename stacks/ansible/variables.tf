variable "targets" {
  type = map(object({
    kind            = string
    name            = string
    node            = string
    address         = any
    tags            = list(string)
    ansible_enabled = bool
  }))
  default     = {}
  description = "Targets exported by proxmox-base."
}
