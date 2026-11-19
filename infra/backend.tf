
#o backend do terraform signifca o lugar aonde vai ser armazenado o statefile

terraform {
  backend "s3" {
    bucket       = "miguel-aluguel-tfstate-pi04"
    key          = "miguel-aluguel/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
