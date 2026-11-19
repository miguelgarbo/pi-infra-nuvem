# =====================================================================
# ALTA DISPONIBILIDADE (Moroni)
# Na projecao atual o projeto tem alguns SPOFs: Nginx único, NAT único, falta de 2ª subnet pública
# e falta de health check nas tasks.
# =====================================================================

# ---------------------------------------------------------------------
# 1) 2ª subnet pública (us-east-1b). O ALB exige subnets em 2 AZs.
# ---------------------------------------------------------------------
resource "aws_subnet" "subnet-pub-2" {
  vpc_id                  = aws_vpc.vpc_miguel_aluguel.id
  cidr_block              = "10.20.3.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = false

  tags = {
    Name = "subnet-pub-2"
  }
}

resource "aws_route_table_association" "assoc-pb-2" {
  subnet_id      = aws_subnet.subnet-pub-2.id
  route_table_id = aws_route_table.rt_public.id
}

# ---------------------------------------------------------------------
# 2) 2º NAT Gateway (um por AZ) + tabela de rotas privada da AZ 1b
#    A AZ 1a continua usando o NAT original (rt_private).
# ---------------------------------------------------------------------
resource "aws_eip" "nat_eip_2" {
  domain     = "vpc"
  depends_on = [aws_internet_gateway.igw]

  tags = {
    Name = "eip-nat-2-miguel-aluguel"
  }
}

resource "aws_nat_gateway" "nat_2" {
  allocation_id = aws_eip.nat_eip_2.id
  subnet_id     = aws_subnet.subnet-pub-2.id
  depends_on    = [aws_internet_gateway.igw]

  tags = {
    Name = "natzao-2-miguel-aluguel"
  }
}

resource "aws_route_table" "rt_private_2" {
  vpc_id = aws_vpc.vpc_miguel_aluguel.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_2.id
  }

  tags = {
    Name = "rt-private-2"
  }
}

# ---------------------------------------------------------------------
# 3) Security group do ALB
# ---------------------------------------------------------------------
resource "aws_security_group" "alb" {
  name        = "alb-pi"
  description = "Acesso publico ao Application Load Balancer"
  vpc_id      = aws_vpc.vpc_miguel_aluguel.id
  tags        = { Name = "alb-pi" }
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTP"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "alb_to_front" {
  security_group_id            = aws_security_group.alb.id
  description                  = "ALB para o frontend"
  from_port                    = 80
  to_port                      = 80
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.front-pi.id
}

resource "aws_vpc_security_group_egress_rule" "alb_to_back" {
  security_group_id            = aws_security_group.alb.id
  description                  = "ALB para o backend"
  from_port                    = 8080
  to_port                      = 8080
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.back-pi.id
}

# Frontend e backend passam a aceitar tráfego do ALB (e não mais do Nginx)
resource "aws_vpc_security_group_ingress_rule" "front_from_alb" {
  security_group_id            = aws_security_group.front-pi.id
  description                  = "HTTP do ALB"
  from_port                    = 80
  to_port                      = 80
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.alb.id
}

resource "aws_vpc_security_group_ingress_rule" "back_from_alb" {
  security_group_id            = aws_security_group.back-pi.id
  description                  = "HTTP do ALB"
  from_port                    = 8080
  to_port                      = 8080
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.alb.id
}

# ---------------------------------------------------------------------
# 4) Application Load Balancer (multi-AZ) substitui o Nginx
# ---------------------------------------------------------------------
resource "aws_lb" "app" {
  name                       = "miguel-aluguel-alb"
  load_balancer_type         = "application"
  internal                   = false
  security_groups            = [aws_security_group.alb.id]
  subnets                    = [aws_subnet.subnet-pub-1.id, aws_subnet.subnet-pub-2.id]
  drop_invalid_header_fields = true

  depends_on = [aws_internet_gateway.igw]

  tags = {
    Name = "alb-miguel-aluguel"
  }
}

# Target group do FRONTEND (porta 80)
resource "aws_lb_target_group" "frontend" {
  name                 = "tg-miguel-frontend"
  port                 = 80
  protocol             = "HTTP"
  target_type          = "ip" # obrigatório para Fargate (awsvpc)
  vpc_id               = aws_vpc.vpc_miguel_aluguel.id
  deregistration_delay = 30

  health_check {
    path                = "/"
    matcher             = "200-399"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

# Target group do BACKEND (porta 8080)
resource "aws_lb_target_group" "backend" {
  name                 = "tg-miguel-backend"
  port                 = 8080
  protocol             = "HTTP"
  target_type          = "ip"
  vpc_id               = aws_vpc.vpc_miguel_aluguel.id
  deregistration_delay = 30

  health_check {
    # AJUSTAR: troque "/" por um endpoint real de saúde do backend
    # (ex.: /actuator/health se for Spring Boot com actuator).
    # O matcher largo (200-499) só confirma que a app responde HTTP.
    path                = "/"
    matcher             = "200-499"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

# Listener: tudo vai para o frontend, exceto /api/*
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.frontend.arn
  }
}

resource "aws_lb_listener_rule" "api" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend.arn
  }

  condition {
    path_pattern {
      values = ["/api/*"]
    }
  }
}

# ---------------------------------------------------------------------
# 5) Auto scaling dos serviços ECS (gravidade baixa)
#    Mínimo 2 tasks (uma por AZ), sobe até 4 se a CPU passar de 60%.
# ---------------------------------------------------------------------
resource "aws_appautoscaling_target" "backend" {
  max_capacity       = 4
  min_capacity       = 2
  resource_id        = "service/${aws_ecs_cluster.pi_cluster.name}/${aws_ecs_service.backend_service.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "backend_cpu" {
  name               = "backend-cpu"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.backend.resource_id
  scalable_dimension = aws_appautoscaling_target.backend.scalable_dimension
  service_namespace  = aws_appautoscaling_target.backend.service_namespace

  target_tracking_scaling_policy_configuration {
    target_value       = 60
    scale_in_cooldown  = 120
    scale_out_cooldown = 60

    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
  }
}

resource "aws_appautoscaling_target" "frontend" {
  max_capacity       = 4
  min_capacity       = 2
  resource_id        = "service/${aws_ecs_cluster.pi_cluster.name}/${aws_ecs_service.frontend_service.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "frontend_cpu" {
  name               = "frontend-cpu"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.frontend.resource_id
  scalable_dimension = aws_appautoscaling_target.frontend.scalable_dimension
  service_namespace  = aws_appautoscaling_target.frontend.service_namespace

  target_tracking_scaling_policy_configuration {
    target_value       = 60
    scale_in_cooldown  = 120
    scale_out_cooldown = 60

    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
  }
}
