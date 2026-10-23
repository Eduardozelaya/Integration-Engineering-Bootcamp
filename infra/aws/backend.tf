# Estado do alarme de custo no S3 (criado em infra/aws/bootstrap). Trava nativa, sem servico extra.
terraform {
  backend "s3" {
    bucket       = "integration-lab-tfstate-539fbcd0"
    key          = "infra/aws/terraform.tfstate"
    region       = "us-east-2"
    encrypt      = true
    use_lockfile = true
  }
}
