output "ip_public" {
  value = "O IP público do Miguel Aluguel é: ${aws_instance.ec2-nginx-pi.public_ip}"
}