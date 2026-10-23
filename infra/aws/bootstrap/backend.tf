# O estado do proprio bootstrap tambem fica no bucket que ele criou (migrado depois do 1o apply).
terraform {
  backend "s3" {
    bucket       = "integration-lab-tfstate-539fbcd0"
    key          = "bootstrap/terraform.tfstate"
    region       = "us-east-2"
    encrypt      = true
    use_lockfile = true
  }
}
