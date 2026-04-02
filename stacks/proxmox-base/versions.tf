terraform {
  required_version = ">= 1.5.0, < 2.0.0"

  required_providers {
    http = {
      source  = "hashicorp/http"
      version = "~> 3.4"
    }

    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.66, < 1.0.0"
    }
  }
}
