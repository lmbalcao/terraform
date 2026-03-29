terraform {
  required_version = ">= 1.5.0, < 2.0.0"

  required_providers {
    http = {
      source  = "hashicorp/http"
      version = "~> 3.4"
    }

    proxmox = {
      source  = "Telmate/proxmox"
      version = "= 3.0.2-rc07"
    }
  }
}
