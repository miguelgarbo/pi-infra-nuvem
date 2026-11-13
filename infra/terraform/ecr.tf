resource "aws_ecr_repository" "ecr_backend" {
  name         = "miguel-aluguel-backend"
  force_delete = false
}

resource "aws_ecr_repository" "ecr_frontend" {
  name                 = "miguel-aluguel-frontend"
  image_tag_mutability = "MUTABLE"
  force_delete         = false
}
