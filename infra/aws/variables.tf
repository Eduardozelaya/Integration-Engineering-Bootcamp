variable "regiao" {
  description = "Regiao de trabalho do lab (docs/aws-conta.md)"
  type        = string
  default     = "us-east-2"
}

variable "email_alerta" {
  description = "E-mail que recebe os alertas de custo. Fora do git: export TF_VAR_email_alerta=..."
  type        = string
  sensitive   = true

  # Duas vezes em 22/10 o valor de exemplo foi colado (SEU_EMAIL, exemplo.com); na 2a, o plan propos
  # destruir a inscricao confirmada. A validacao recusa isso antes de qualquer plano.
  validation {
    condition     = can(regex("^[^@[:space:]]+@[^@[:space:]]+\\.[a-z]{2,}$", var.email_alerta)) && !strcontains(lower(var.email_alerta), "exemplo") && !strcontains(var.email_alerta, "SEU_")
    error_message = "email_alerta invalido ou de exemplo: confira o export TF_VAR_email_alerta."
  }
}
