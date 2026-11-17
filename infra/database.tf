
resource "aws_db_instance" "postgres_rds" {
  identifier             = "miguel-aluguel-db"
  engine                 = "postgres"
  engine_version         = "17"
  instance_class         = "db.t3.micro"
  allocated_storage      = 20
  db_name                = var.DB_NAME
  username               = var.DB_USERNAME
  password               = var.DB_PASSWORD
  db_subnet_group_name   = aws_db_subnet_group.db_subnet_group.name
  vpc_security_group_ids = [aws_security_group.rds-pi.id]
  skip_final_snapshot    = true
  publicly_accessible    = false

  multi_az = true

  # ---------- Criptografia em repouso (S6) ----------
  # Declarada explicitamente, mesmo sendo o padrão em contas novas.
  # Sem kms_key_id, o RDS usa a chave gerenciada pela AWS (aws/rds).
  # Os backups automáticos e snapshots herdam a criptografia da instância.
  storage_encrypted = true

  # ---------- Política mínima de backup (Parte D, seção 6.3 / B6) ----------
  # Geração Son do GFS: backup automático diário do próprio RDS,
  # com retenção curta para manter o custo próximo de zero.
  backup_retention_period = var.db_backup_retention_days
  backup_window           = var.db_backup_window
  copy_tags_to_snapshot   = true

  # Ao destruir o banco, apaga também os backups automáticos,
  # para que nada fique sendo cobrado depois do terraform destroy (seção 11).
  delete_automated_backups = true

  # As janelas de backup e manutenção não podem se sobrepor.
  maintenance_window = var.db_maintenance_window
}

# Subnet Group do RDS
# aqui informa as subnets/zonas que o rds pode usar 
resource "aws_db_subnet_group" "db_subnet_group" {
  name       = "db-subnet-group"
  subnet_ids = [aws_subnet.subnet-priv-1.id, aws_subnet.subnet-priv-2.id]

  tags = {
    Name = "DB Subnet Group"
  }
}
