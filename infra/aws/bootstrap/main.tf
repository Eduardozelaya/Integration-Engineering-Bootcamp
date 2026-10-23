# Bootstrap: o bucket S3 que guarda o ESTADO do Terraform do lab (infra/aws e este proprio).
# Criado com estado local; depois, os dois estados sao migrados para dentro dele (backend.tf).
terraform {
  required_version = ">= 1.16"
  required_providers {
    aws    = { source = "hashicorp/aws", version = ">= 6.0" }
    random = { source = "hashicorp/random", version = ">= 3.6" }
  }
}

provider "aws" {
  region = "us-east-2"
  default_tags {
    tags = { Projeto = "integration-lab", Gerenciado = "terraform" }
  }
}

# Nome de bucket e unico no mundo: sufixo aleatorio, sem expor o numero da conta.
resource "random_id" "sufixo" {
  byte_length = 4
}

resource "aws_s3_bucket" "estado" {
  bucket = "integration-lab-tfstate-${random_id.sufixo.hex}"
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "estado" {
  bucket = aws_s3_bucket.estado.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "estado" {
  bucket                  = aws_s3_bucket.estado.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "estado" {
  bucket = aws_s3_bucket.estado.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

output "bucket" {
  value = aws_s3_bucket.estado.bucket
}
