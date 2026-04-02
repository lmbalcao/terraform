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

variable "proxmox_password" {
  type        = string
  sensitive   = true
  description = "Proxmox root@pam password used by the provider. Required for bind-mount operations (Proxmox enforces root@pam identity at the API level)."

  validation {
    condition = (
      trimspace(var.proxmox_password) != "" &&
      !contains([
        "REPLACE_ME",
        "<proxmox-root-password>",
      ], trimspace(var.proxmox_password))
    )
    error_message = "proxmox_password must be set to the real root@pam password. Placeholder values do not validate the stack."
  }
}

# Kept as optional declarations so tfvars files that include these keys
# (e.g. for terraform-gui direct API calls) do not cause Terraform errors.
variable "proxmox_api_token_id" {
  type      = string
  default   = null
  nullable  = true
  sensitive = false
  description = "Proxmox API token ID. Not used by this stack's provider (password auth is required for bind mounts); retained so GUI tfvars files remain valid."
}

variable "proxmox_api_token" {
  type      = string
  default   = null
  nullable  = true
  sensitive = true
  description = "Proxmox API token secret. Not used by this stack's provider; retained so GUI tfvars files remain valid."
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

variable "docker_apps_root" {
  type        = string
  default     = null
  nullable    = true
  description = "Optional local override root used mainly for tests; when null, app docker-compose files are fetched from the canonical remote repository."
}

variable "compose_source_base_url" {
  type        = string
  default     = "https://raw.githubusercontent.com/lmbalcao/docker/main"
  description = "Canonical base URL used to resolve app docker-compose.yml files when docker_apps_root is null."
}

variable "proxmox_ssh_host" {
  type        = string
  default     = null
  nullable    = true
  description = "Optional SSH host used for CT feature reconciliation that requires root pct access."
}

variable "proxmox_ssh_port" {
  type        = number
  default     = 22
  description = "SSH port used for CT feature reconciliation."
}

variable "proxmox_ssh_user" {
  type        = string
  default     = "root"
  description = "SSH user used for CT feature reconciliation."
}

variable "proxmox_ssh_private_key_path" {
  type        = string
  default     = null
  nullable    = true
  description = "Optional private key path used for CT feature reconciliation over SSH."
}

variable "guest_ssh_user" {
  type        = string
  default     = "root"
  description = "SSH user used to prepare app bind-mount paths inside VMs."
}

variable "guest_ssh_port" {
  type        = number
  default     = 22
  description = "SSH port used to prepare app bind-mount paths inside VMs."
}

variable "guest_ssh_private_key_path" {
  type        = string
  default     = null
  nullable    = true
  description = "Private key path used to prepare app bind-mount paths inside VMs. Required when enabled VMs declare apps."
}
