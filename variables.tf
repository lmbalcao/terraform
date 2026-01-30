###############################################################################
# Proxmox
###############################################################################

variable "proxmox_api_url" {
  type        = string
  description = "URL da API do Proxmox (ex: https://pve:8006/api2/json)"
}

variable "proxmox_api_token_id" {
  type        = string
  description = "Token ID do Proxmox (ex: terraform@pve!token)"
}

variable "proxmox_api_token" {
  type        = string
  sensitive   = true
  description = "Token secreto da API do Proxmox"
}

###############################################################################
# Sistema / LXC
###############################################################################

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

variable "ssh_private_key_path" {
  type        = string
  description = "Caminho local da private key usada para SSH ao CT"
}

variable "ostemplate" {
  type        = string
  description = "Template LXC (ex: local:vztmpl/debian-13-standard_amd64.tar.zst)"
}

variable "searchdomain" {
  type        = string
  description = "Search domain DNS (ex: lbtec.org)"
}

###############################################################################
# Rundeck
###############################################################################

variable "rundeck_url" {
  type        = string
  description = "URL do servidor Rundeck"
}

variable "rundeck_api_token" {
  type        = string
  sensitive   = true
  description = "API token do Rundeck"
}

variable "rundeck_project" {
  type        = string
  description = "Nome do projeto Rundeck"
}

variable "rundeck_job_id" {
  type        = string
  description = "ID do job Rundeck a executar após criação do CT"
}

###############################################################################
# Aplicações / Forgejo
###############################################################################

variable "apps_repo_url" {
  type        = string
  description = "URL HTTPS do repositório de aplicações (Forgejo/Git)"
}

variable "apps_repo_branch" {
  type        = string
  default     = "main"
  description = "Branch a usar no repositório de aplicações"
}

variable "forgejo_user" {
  description = "Utilizador Forgejo para autenticação HTTPS"
  type        = string
}

variable "forgejo_token" {
  type        = string
  default     = ""
  sensitive   = true
  description = "Token Forgejo (repo privado). Deixar vazio se público."
}
