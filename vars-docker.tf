###############################################################################
# Aplicações / Forgejo
###############################################################################

variable "apps_repo_url" {
  type        = string
  description = "URL HTTPS do repositório de aplicações (Forgejo/Git)"
}

variable "apps_repo_branch" {
  type        = string
  default     = "main"
  description = "Branch a usar no repositório de aplicações"
}

variable "forgejo_user" {
  description = "Utilizador Forgejo para autenticação HTTPS"
  type        = string
}

variable "forgejo_token" {
  type        = string
#  sensitive   = true
  description = "Token Forgejo (repo privado). Deixar vazio se público."
}

###############################################################################
# Deploy Control
###############################################################################

variable "force_redeploy_timestamp" {
  type        = string
  default     = ""
  description = "Timestamp para forçar re-deploy de aplicações (opcional, formato: YYYY-MM-DD-HH-MM-SS)"
}