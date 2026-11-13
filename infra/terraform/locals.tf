#tags que vao ser usadas para filtrar os recursos criados,
#e tambem para identificar o projeto em si
locals {
  project_name = "miguel-aluguel-terraform-infra"

  common_tags = {
    Project     = local.project_name
    Environment = "lab"
    ManagedBy   = "Terraform"
  }
}