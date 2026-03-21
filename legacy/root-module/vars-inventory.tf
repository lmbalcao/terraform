###############################################################################
# vars-inventory.tf - Variáveis específicas do inventário
###############################################################################

variable "ostemplate" {
  type        = string
  description = "Template LXC (ex: local:vztmpl/debian-13-standard_amd64.tar.zst)"
}