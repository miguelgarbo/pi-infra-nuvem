#declaração de variavel existente no codigo
#pode se definir um valor default para a variavel,
#caso não seja definido um valor no arquivo terraform.tfvars
variable "aws_region" {
  description = "Regiao da AWS onde os recursos serao criados"
  type        = string
  default     = "us-east-1"
}

variable "ecr_frontend" {
  description = "Repositório Privado do Front do Miguel aluguel "
  type        = string
}

variable "ecr_backend" {
  description = "Repositório Privado do Back do Miguel aluguel "
  type        = string
}

variable "HASH_TOKEN" {
  description = "Hash para o JWT"
  type        = string
}

variable "DB_USERNAME" {
  description = "Usuário do banco para a aplicação"
  type        = string
}
variable "DB_NAME" {
  description = "Nome do banco para a aplicação"
  type        = string
}

variable "DB_PASSWORD" {
  description = "Senha do usuário do banco para a aplicação"
  type        = string
}

# ---------- Backup do banco (Parte D) ----------

variable "db_backup_retention_days" {
  description = "Dias de retenção dos backups automáticos do RDS (política mínima: no máximo 2 dias, seção 6.3)"
  type        = number
  default     = 2

  validation {
    condition     = var.db_backup_retention_days >= 1 && var.db_backup_retention_days <= 2
    error_message = "A política mínima exige retenção entre 1 e 2 dias. Valor 0 desativa o backup e acima de 2 viola a seção 6.3."
  }
}

variable "db_backup_window" {
  description = "Janela diária do backup automático do RDS, em UTC (hh24:mi-hh24:mi, mínimo 30 minutos)"
  type        = string
  default     = "06:00-06:30" # 03:00-03:30 em Brasília, fora do horário de uso
}

variable "db_maintenance_window" {
  description = "Janela semanal de manutenção do RDS, em UTC (ddd:hh24:mi-ddd:hh24:mi); não pode sobrepor a janela de backup"
  type        = string
  default     = "sun:07:00-sun:07:30"
}

