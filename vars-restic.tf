###############################################################################
# Restic Backup
# ⚠️ NOTA: proxmox_nodes está em vars-proxmox.tf
###############################################################################

variable "restic_password" {
  type        = string
  sensitive   = true
  description = "Password do repositório Restic para restore"
}

variable "restic_repository" {
  type        = string
  description = "Caminho do repositório Restic no host Proxmox"
}

variable "ssh_private_key_path" {
  type        = string
  description = "Caminho da chave SSH privada para acesso aos nodes Proxmox"
}