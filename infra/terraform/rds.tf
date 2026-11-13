
resource "aws_db_instance" "postgres_rds" {
  identifier             = "miguel-aluguel-db"
  engine                 = "postgres"
  engine_version         = "17"
  instance_class         = "db.t3.micro"
  allocated_storage      = 20
  db_name                = "miguel_aluguel"
  username               = "postgres"
  password               = "postgres" 
  db_subnet_group_name   = aws_db_subnet_group.db_subnet_group.name
  vpc_security_group_ids = [aws_security_group.rds-pi.id]
  skip_final_snapshot    = true
  publicly_accessible    = false
}
