variable "environment" {
  type        = string
  description = "Inventory environment name."
}

variable "inventory_root" {
  type        = string
  default     = "../../inventory"
  description = "Path from this stack to the inventory root."
}

variable "proxmox_api_url" {
  type        = string
  description = "Proxmox API URL. Can be set via tfvars or TF_VAR_proxmox_api_url."

  validation {
    condition = (
      trimspace(var.proxmox_api_url) != "" &&
      !contains([
        "REPLACE_ME",
        "<proxmox-api-url>",
      ], trimspace(var.proxmox_api_url))
    )
    error_message = "proxmox_api_url must be set to a real Proxmox API URL. Placeholder values do not validate the stack."
  }
}

variable "proxmox_api_token_id" {
  type        = string
  description = "Proxmox API token ID in the form user@realm!token-name. Can be set via tfvars or TF_VAR_proxmox_api_token_id."

  validation {
    condition = (
      trimspace(var.proxmox_api_token_id) != "" &&
      !contains([
        "REPLACE_ME",
        "<proxmox-api-token-id>",
        "<proxmox-user@realm!token-name>",
      ], trimspace(var.proxmox_api_token_id))
    )
    error_message = "proxmox_api_token_id must be set to a real Proxmox API token ID. Placeholder values do not validate the stack."
  }
}

variable "proxmox_api_token" {
  type        = string
  sensitive   = true
  description = "Proxmox API token secret. Can be set via tfvars or TF_VAR_proxmox_api_token."

  validation {
    condition = (
      trimspace(var.proxmox_api_token) != "" &&
      !contains([
        "REPLACE_ME",
        "<proxmox-api-token-secret>",
      ], trimspace(var.proxmox_api_token))
    )
    error_message = "proxmox_api_token must be set to a real Proxmox API token secret. Placeholder values do not validate the stack."
  }
}

variable "proxmox_tls_insecure" {
  type        = bool
  default     = true
  description = "Disable TLS verification for Proxmox API requests used by proxmox-base."
}

variable "root_password" {
  type        = string
  sensitive   = true
  description = "Bootstrap root password for CTs."

  validation {
    condition = (
      trimspace(var.root_password) != "" &&
      !contains([
        "REPLACE_ME",
        "<ct-root-password>",
      ], trimspace(var.root_password))
    )
    error_message = "root_password must be set to a real bootstrap password. Placeholder values do not validate the stack."
  }
}

variable "ssh_public_keys" {
  type        = list(string)
  default     = []
  description = "SSH public keys injected in CTs."
}

variable "default_search_domain" {
  type        = string
  default     = null
  nullable    = true
  description = "Fallback DNS search domain."
}

variable "default_lxc_template" {
  type        = string
  default     = null
  nullable    = true
  description = "Fallback LXC template if inventory does not define one. Prefer explicit per-CT templates when proven by real inventory."
}

variable "network_bridge" {
  type        = string
  default     = "vmbr0"
  description = "Fallback bridge name."
}
