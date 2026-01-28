# Terraform -> indica quais vai usar
terraform {
  required_providers {
    proxmox = {
      source  = "Telmate/proxmox"
      version = "= 3.0.2-rc07"
    }

    rundeck = {
      source  = "rundeck/rundeck"
      version = "0.4.7"
    }
  }
}

# Configuracoes inviduais de cada provider 

# Proxmox 
provider "proxmox" {
  # Configuration options
  pm_api_url = var.proxmox_api_url
  pm_api_token_id =  var.proxmox_api_token_id
  pm_api_token_secret =  var.proxmox_api_token
  pm_tls_insecure = true
}

# Rundeck
provider "rundeck" {
  url         = var.rundeck_url
  api_version = "38"
  auth_token  = var.rundeck_api_token
}
