###############################################################################
# Rundeck
###############################################################################

variable "rundeck_url" {
  type        = string
  description = "URL do servidor Rundeck"
}

variable "rundeck_api_token" {
  type        = string
  sensitive   = true
  description = "API token do Rundeck"
}

variable "rundeck_project" {
  type        = string
  description = "Nome do projeto Rundeck"
}

variable "rundeck_job_id" {
  type        = string
  description = "ID do job Rundeck a executar após criação do CT"
}


