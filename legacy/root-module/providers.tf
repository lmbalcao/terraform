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

    portainer = {
      source  = "portainer/portainer"
      version = "~> 1.23.0"
    }
  }
}

# Configuracoes individuais de cada provider 

# Proxmox 
provider "proxmox" {
  pm_api_url          = var.proxmox_api_url
  pm_api_token_id     = var.proxmox_api_token_id
  pm_api_token_secret = var.proxmox_api_token
  pm_tls_insecure     = true
}

# Rundeck
provider "rundeck" {
  url         = var.rundeck_url
  api_version = "38"
  auth_token  = var.rundeck_api_token
}

# Portainer
provider "portainer" {
  endpoint        = var.portainer_endpoint
  api_key         = var.portainer_api_key
  skip_ssl_verify = var.portainer_skip_ssl_verify
}