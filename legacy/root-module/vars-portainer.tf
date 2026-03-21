# vars-portainer.tf

variable "portainer_endpoint" {
  description = "URL do Portainer"
  type        = string
}

variable "portainer_api_key" {
  description = "API Key do Portainer"
  type        = string
  sensitive   = true
}

variable "portainer_skip_ssl_verify" {
  description = "Skip SSL verification"
  type        = bool
  default     = false
}

variable "portainer_join_token" {
  description = "Token para join de agents ao Portainer"
  type        = string
  sensitive   = true
}

variable "portainer_server_ip" {
  description = "IP do servidor Portainer para acesso Docker TLS API"
  type        = string
  default     = "192.168.35.10"
}