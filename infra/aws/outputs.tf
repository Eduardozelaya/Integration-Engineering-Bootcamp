output "topico" {
  value = aws_sns_topic.alertas.name
}
output "orcamento" {
  value = aws_budgets_budget.gasto_zero.name
}
output "ecr_wiremock" {
  value = aws_ecr_repository.wiremock.name
}
