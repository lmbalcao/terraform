# Variaveis usadas

variable "proxmox_api_url" {
    type = string
  
}

variable "proxmox_api_token_id" {
    type = string
  
}

variable "proxmox_api_token" {
    type = string
  
}

variable "root_password" {
    type = string
  
}

variable "ssh_public_keys" {
  description = "Lista de chaves SSH públicas a injetar no LXC"
  type        = list(string)
  default     = []
}

variable "ostemplate" {
    type = string
  
}

variable "searchdomain" {
    type = string
  
}