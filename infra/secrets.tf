# ---------- Gestão de segredos (S4) ----------
# Os valores chegam por variáveis marcadas como sensitive (variables.tf),
# fornecidas pelo terraform.tfvars (fora do Git) ou por TF_VAR_DB_PASSWORD /
# TF_VAR_HASH_TOKEN. Ficam guardados como SecureString no SSM Parameter Store,
# criptografados com a chave KMS gerenciada pela AWS (alias/aws/ssm) (S6).
# Parâmetros do tipo Standard não têm custo.

resource "aws_ssm_parameter" "db_password" {
  name        = "/miguel-aluguel/db/password"
  description = "Senha do usuario da aplicacao no RDS PostgreSQL"
  type        = "SecureString"
  value       = var.DB_PASSWORD
}

resource "aws_ssm_parameter" "hash_token" {
  name        = "/miguel-aluguel/app/hash-token"
  description = "Segredo usado pelo backend para assinar os tokens JWT"
  type        = "SecureString"
  value       = var.HASH_TOKEN
}
