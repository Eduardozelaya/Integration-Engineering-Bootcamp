# Registro privado de imagens do lab (ECR). Estreia com o WireMock (Apache 2.0): o ACE nao pode ser
# redistribuido (ADR 002) e o MQ de desenvolvedor tem licenca propria.
resource "aws_ecr_repository" "wiremock" {
  name                 = "integration-lab/wiremock"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
  encryption_configuration {
    encryption_type = "AES256"
  }
}

# Sem esta regra, cada push acumula armazenamento (e custo) para sempre.
resource "aws_ecr_lifecycle_policy" "wiremock" {
  repository = aws_ecr_repository.wiremock.name
  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "imagens sem tag: apagar depois de 1 dia"
        selection    = { tagStatus = "untagged", countType = "sinceImagePushed", countUnit = "days", countNumber = 1 }
        action       = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "manter so as 3 imagens mais recentes"
        selection    = { tagStatus = "any", countType = "imageCountMoreThan", countNumber = 3 }
        action       = { type = "expire" }
      }
    ]
  })
}
