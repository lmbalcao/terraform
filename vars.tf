variable "ssh_key" {
    default = "ssh-rsa ....."
}
variable "api_url" {
    # The Proxmox Web UI address, with /api2/json added to it.
    default = "https://192.168.1.15:8006/api2/json" 
}
variable "proxmox_host" {
    # The name of the Proxmox server listed under Datacenter
    default = "2core" 
}
variable "template_name" {
  default = "template-lxc-priv
}
variable "token_id" {
  default = "terraform@pam!terraform_token_id"
}
variable "token_secret" {
  default = "..." # Enter your API Secret here
}
variable "ipconfig_pihole" {
  default = "ip=192.168.1.16/24,gw=192.168.1.1"
}
variable "ipconfig_homebridge" {
  default = "ip=192.168.1.17/24,gw=192.168.1.1"
}

