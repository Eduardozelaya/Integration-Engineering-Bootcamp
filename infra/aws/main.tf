# Alarme de custo da conta AWS do lab, como codigo (19-22/10).
# O orcamento avisa por um topico SNS: os contatos de e-mail do Budgets sao negados por uma SCP da
# organizacao (docs/aws-conta.md). Credenciais: 'aws login' (temporarias), nenhuma chave fixa.
terraform {
  required_version = ">= 1.16"
  required_providers {
    aws = { source = "hashicorp/aws", version = ">= 6.0" }
  }
}

provider "aws" {
  region = var.regiao
  default_tags {
    tags = { Projeto = "integration-lab", Gerenciado = "terraform" }
  }
}

data "aws_caller_identity" "conta" {}

resource "aws_sns_topic" "alertas" {
  name = "lab-alertas-custo"
}

# So o AWS Budgets, e so em nome DESTA conta, pode publicar no topico.
resource "aws_sns_topic_policy" "alertas" {
  arn = aws_sns_topic.alertas.arn
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "BudgetsPublica"
      Effect    = "Allow"
      Principal = { Service = "budgets.amazonaws.com" }
      Action    = "SNS:Publish"
      Resource  = aws_sns_topic.alertas.arn
      Condition = { StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.conta.account_id } }
    }]
  })
}

# A AWS envia um link de confirmacao; sem clicar, a inscricao fica pendente e nada e entregue.
resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alertas.arn
  protocol  = "email"
  endpoint  = var.email_alerta
}

resource "aws_budgets_budget" "gasto_zero" {
  name         = "lab-gasto-zero-sns"
  budget_type  = "COST"
  limit_amount = "1.0"
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  # Medir o uso ANTES dos creditos: no plano gratuito, o gasto liquido e sempre zero.
  cost_types {
    include_credit = false
    include_refund = false
  }

  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = 0.01
    threshold_type            = "ABSOLUTE_VALUE"
    notification_type         = "ACTUAL"
    subscriber_sns_topic_arns = [aws_sns_topic.alertas.arn]
  }

  depends_on = [aws_sns_topic_policy.alertas]
}
