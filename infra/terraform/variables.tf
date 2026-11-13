#declaração de variavel existente no codigo
#pode se definir um valor default para a variavel,
#caso não seja definido um valor no arquivo terraform.tfvars
variable "aws_region" {
  description = "Regiao da AWS onde os recursos serao criados"
  type        = string
  default     = "us-east-1"
}

