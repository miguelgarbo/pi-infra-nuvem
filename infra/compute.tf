# EC2 NGINX (PROXY REVERSO)

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
}

# Instância pública para o Nginx
resource "aws_instance" "ec2-nginx-pi" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t3.micro"
  subnet_id     = aws_subnet.subnet-pub-1.id

  associate_public_ip_address = true

  vpc_security_group_ids = [
    aws_security_group.app_access.id
  ]
  user_data_replace_on_change = true

  iam_instance_profile = aws_iam_instance_profile.ssm_nginx.name

  # ---------- Criptografia em repouso (S6) ----------
  # Disco raiz criptografado, declarado explicitamente (Trivy AWS-0131).
  # Sem kms_key_id, o EBS usa a chave gerenciada pela AWS (aws/ebs).
  root_block_device {
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  # ---------- IMDSv2 obrigatório (S5) ----------
  # Exige token de sessão para ler o metadata service, onde ficam as credenciais
  # temporárias da role da instância. Bloqueia o roubo dessas credenciais
  # por SSRF através do proxy Nginx (Trivy AWS-0028).
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  user_data = <<-EOF
    #!/bin/bash
    set -euxo pipefail

    # Atualiza os pacotes
    apt-get update -y

    # Instala Nginx e ferramentas de diagnóstico
    DEBIAN_FRONTEND=noninteractive apt-get install -y nginx dnsutils curl openssl

    # ---------- S1: endurecimento do SSH ----------
    # Sem login por senha e sem login direto como root. A porta 22 nem está
    # aberta no security group (acesso administrativo pelo SSM), mas o sshd
    # fica endurecido caso alguém libere a porta no futuro.
    cat > /etc/ssh/sshd_config.d/01-hardening.conf <<'SSHD'
    PasswordAuthentication no
    KbdInteractiveAuthentication no
    PermitRootLogin no
    SSHD
    systemctl restart ssh || true

    # ---------- S3: certificado TLS autoassinado ----------
    # O IP público é lido do metadata com IMDSv2 (token obrigatório, ver S5)
    # e entra no certificado como CN e subjectAltName.
    TOKEN=$(curl -sf -X PUT http://169.254.169.254/latest/api/token -H "X-aws-ec2-metadata-token-ttl-seconds: 300") || TOKEN=""
    PUBLIC_IP=$(curl -sf -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/public-ipv4) || PUBLIC_IP="127.0.0.1"
    mkdir -p /etc/nginx/ssl
    openssl req -x509 -nodes -newkey rsa:2048 -days 30 \
      -keyout /etc/nginx/ssl/selfsigned.key -out /etc/nginx/ssl/selfsigned.crt \
      -subj "/CN=$PUBLIC_IP" -addext "subjectAltName=IP:$PUBLIC_IP"
    chmod 600 /etc/nginx/ssl/selfsigned.key

    # Configuração do Nginx
    cat > /etc/nginx/sites-available/default <<'NGINX'

    # HTTP: só redireciona para HTTPS (S3)
    server {
        listen 80 default_server;
        listen [::]:80 default_server;
        server_name _;

        return 301 https://$host$request_uri;
    }

    server {
        listen 443 ssl default_server;
        listen [::]:443 ssl default_server;

        server_name _;

        ssl_certificate     /etc/nginx/ssl/selfsigned.crt;
        ssl_certificate_key /etc/nginx/ssl/selfsigned.key;
        ssl_protocols       TLSv1.2 TLSv1.3;
        server_tokens       off;

        # DNS privado da VPC AWS
        resolver 10.20.0.2 valid=10s ipv6=off;
        resolver_timeout 5s;

        # -----------------------------
        # BACKEND
        # -----------------------------
        location /api/ {
            set $backend backend.miguel-aluguel.internal:8080;

            proxy_pass http://$backend;

            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }

        # -----------------------------
        # FRONTEND
        # -----------------------------
        location / {
            set $frontend frontend.miguel-aluguel.internal:80;

            proxy_pass http://$frontend;

            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }
    }

    NGINX

    # Valida a configuração
    nginx -t

    # Habilita e inicia o serviço
    systemctl enable nginx
    systemctl restart nginx

EOF

  tags = {
    Name = "ec2-nginx-pi"
  }

}



# CLUSTER ECS + FARGATE
resource "aws_ecs_cluster" "pi_cluster" {
  name = "miguel-aluguel-cluster"
}


# CloudWatch Log Groups

resource "aws_cloudwatch_log_group" "backend_logs" {
  name              = "/ecs/miguel-aluguel-backend"
  retention_in_days = 14
}

resource "aws_cloudwatch_log_group" "frontend_logs" {
  name              = "/ecs/miguel-aluguel-frontend"
  retention_in_days = 14
}



# --- TASK DEFINITION: BACKEND ---
resource "aws_ecs_task_definition" "backend_task" {
  family                   = "miguel-aluguel-backend"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]

  cpu    = "256"
  memory = "512"

  execution_role_arn = aws_iam_role.ecs_task_execution_role.arn
  depends_on = [
    aws_iam_role_policy_attachment.ecs_task_execution_policy
  ]
  container_definitions = jsonencode([
    {
      name      = "miguel_aluguel_backend_official"
      image     = var.ecr_backend
      essential = true

      portMappings = [
        {
          containerPort = 8080
          protocol      = "tcp"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"

        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.backend_logs.name
          "awslogs-region"        = "us-east-1"
          "awslogs-stream-prefix" = "ecs"
        }
      }

      environment = [
        {
          name  = "DB_URL"
          value = "jdbc:postgresql://${aws_db_instance.postgres_rds.endpoint}/${var.DB_NAME}"
        },
        {
          name  = "DB_USERNAME"
          value = var.DB_USERNAME
        },
        {
          name  = "FRONT_URL"
          value = "https://${aws_instance.ec2-nginx-pi.public_ip}/"
        }
      ]

      # ---------- Gestão de segredos (S4) ----------
      # A senha do banco e o segredo do JWT não ficam em texto puro na task definition.
      # O agente do ECS lê os parâmetros SecureString do SSM no início da task
      # (com a role de execução, ver iam.tf) e os entrega ao container como variáveis
      # de ambiente. Na task definition e no console aparece só o ARN do parâmetro.
      secrets = [
        {
          name      = "DB_PASSWORD"
          valueFrom = aws_ssm_parameter.db_password.arn
        },
        {
          name      = "HASH_TOKEN"
          valueFrom = aws_ssm_parameter.hash_token.arn
        }
      ]


    }
  ])
}

# ECS Service (Mantém o container rodando na EC2)
resource "aws_ecs_service" "backend_service" {
  name            = "backend-service"
  cluster         = aws_ecs_cluster.pi_cluster.id
  task_definition = aws_ecs_task_definition.backend_task.arn

  desired_count = 2
  launch_type   = "FARGATE"

  network_configuration {
    subnets = toset([
      aws_subnet.subnet-priv-1.id,
      aws_subnet.subnet-priv-2.id
    ])
    security_groups = [aws_security_group.back-pi.id]
  }

  service_registries {
    registry_arn = aws_service_discovery_service.backend.arn
  }


}

# --- TASK DEFINITION: FRONTEND ---
resource "aws_ecs_task_definition" "frontend_task" {
  family                   = "miguel-aluguel-frontend"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]

  cpu    = "256"
  memory = "512"

  execution_role_arn = aws_iam_role.ecs_task_execution_role.arn

  depends_on = [
    aws_iam_role_policy_attachment.ecs_task_execution_policy
  ]

  container_definitions = jsonencode([
    {
      name      = "miguel_aluguel_frontend"
      image     = var.ecr_frontend
      essential = true
      portMappings = [
        {
          containerPort = 80
          protocol      = "tcp"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"

        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.frontend_logs.name
          "awslogs-region"        = "us-east-1"
          "awslogs-stream-prefix" = "ecs"
        }
      }

      environment = [
        { name = "VITE_API_URL", value = "https://${aws_instance.ec2-nginx-pi.public_ip}/api" }
      ]
    }
  ])
}

resource "aws_ecs_service" "frontend_service" {
  name            = "frontend-service"
  cluster         = aws_ecs_cluster.pi_cluster.id
  task_definition = aws_ecs_task_definition.frontend_task.arn

  desired_count = 2
  launch_type   = "FARGATE"

  network_configuration {
    subnets = toset([
      aws_subnet.subnet-priv-1.id,
      aws_subnet.subnet-priv-2.id
    ])
    security_groups = [aws_security_group.front-pi.id]
  }

  service_registries {
    registry_arn = aws_service_discovery_service.frontend.arn
  }
}
