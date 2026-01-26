# Proxmox Telmate
terraform {
  required_providers {
    proxmox = {
      source  = "Telmate/proxmox"
      version = "= 3.0.2-rc07"
    }
  }
}

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

provider "proxmox" {
  # Configuration options
  pm_api_url = var.proxmox_api_url
  pm_api_token_id =  var.proxmox_api_token_id
  pm_api_token_secret =  var.proxmox_api_token
  pm_tls_insecure = true
}

