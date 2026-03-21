###############################################################################
# Variáveis para proxmox_ct.tf
###############################################################################

variable "proxmox_nodes" {
  type        = map(string)
  description = "Mapeamento de node name para IP/hostname"
}

variable "root_password" {
  type        = string
  sensitive   = true
  description = "Password de root do LXC (apenas para bootstrap inicial)"
}

variable "ssh_public_keys" {
  type        = list(string)
  default     = []
  description = "Lista de chaves SSH públicas a injetar no LXC"
}

variable "searchdomain" {
  type        = string
  description = "Search domain DNS (ex: lbtec.org)"
}