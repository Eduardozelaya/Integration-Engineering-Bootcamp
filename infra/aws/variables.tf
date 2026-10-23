variable "regiao" {
  description = "Regiao de trabalho do lab (docs/aws-conta.md)"
  type        = string
  default     = "us-east-2"
}

variable "email_alerta" {
  description = "E-mail que recebe os alertas de custo. Fora do git: export TF_VAR_email_alerta=..."
  type        = string
  sensitive   = true
}
