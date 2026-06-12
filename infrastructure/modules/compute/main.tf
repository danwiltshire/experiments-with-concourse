data "aws_vpc" "concourse" {
  filter {
    name   = "tag:Name"
    values = ["concourse"]
  }
}

data "aws_subnets" "private" {
  filter {
    name   = "tag:Name"
    values = ["concourse-private-*"]
  }
}

data "aws_subnets" "public" {
  filter {
    name   = "tag:Name"
    values = ["concourse-public-*"]
  }
}

data "aws_route53_zone" "public" {
  name         = "danforge.net."
  private_zone = false
}

data "aws_route53_zone" "private" {
  name         = "int.danforge.net."
  private_zone = true
}

resource "aws_iam_role" "ecs_instance" {
  name = "concourse-${var.environment_name}-ecs-instance"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "sts:AssumeRole"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachments_exclusive" "ecs_instance" {
  role_name = aws_iam_role.ecs_instance.name
  policy_arns = [
    "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role",
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
  ]
}

resource "aws_iam_instance_profile" "ecs_instance" {
  name = "concourse-${var.environment_name}-ecs-instance"
  role = aws_iam_role.ecs_instance.name
}

resource "aws_security_group" "managed_instances" {
  name        = "concourse-${var.environment_name}-managed-instances"
  description = "Concourse managed instances security group"
  vpc_id      = data.aws_vpc.concourse.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "ecs_tasks" {
  name        = "concourse-${var.environment_name}-ecs-tasks"
  description = "Concourse ECS tasks security group"
  vpc_id      = data.aws_vpc.concourse.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_ecs_cluster" "this" {
  name = "concourse-${var.environment_name}"
}

resource "aws_ecs_cluster_capacity_providers" "this" {
  cluster_name       = aws_ecs_cluster.this.name
  capacity_providers = [aws_ecs_capacity_provider.this.name]

  default_capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = aws_ecs_capacity_provider.this.name
  }
}

data "aws_ssm_parameter" "ecs_ami" {
  name = "/aws/service/ecs/optimized-ami/amazon-linux-2023/recommended/image_id"
}

resource "aws_launch_template" "ecs" {
  name_prefix            = "concourse-${var.environment_name}-ecs-"
  image_id               = data.aws_ssm_parameter.ecs_ami.value
  instance_type          = "t3.large"
  vpc_security_group_ids = [aws_security_group.managed_instances.id]

  iam_instance_profile {
    arn = aws_iam_instance_profile.ecs_instance.arn
  }

  monitoring {
    enabled = true
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size = 30
      volume_type = "gp3"
    }
  }

  user_data = base64encode(<<-EOT
    #!/bin/bash
    echo ECS_CLUSTER=${aws_ecs_cluster.this.name} >> /etc/ecs/ecs.config
    echo "user.max_user_namespaces=15000" > /etc/sysctl.d/99-user-ns.conf
    sysctl --system
  EOT
  )

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "ecs" {
  name_prefix           = "concourse-${var.environment_name}-ecs-"
  min_size              = 1
  max_size              = 3
  desired_capacity      = 1
  vpc_zone_identifier   = data.aws_subnets.private.ids
  protect_from_scale_in = true

  launch_template {
    id      = aws_launch_template.ecs.id
    version = aws_launch_template.ecs.latest_version
  }

  lifecycle {
    create_before_destroy = true
  }

  tag {
    key                 = "AmazonECSManaged"
    value               = true
    propagate_at_launch = true
  }
}

resource "aws_ecs_capacity_provider" "this" {
  name = "concourse-${var.environment_name}"

  auto_scaling_group_provider {
    auto_scaling_group_arn         = aws_autoscaling_group.ecs.arn
    managed_termination_protection = "ENABLED"

    managed_scaling {
      status                    = "ENABLED"
      minimum_scaling_step_size = 1
      maximum_scaling_step_size = 10
      target_capacity           = 100
    }
  }
}



# ECS service role — required for ALB integration with bridge network mode
# resource "aws_iam_role" "ecs_service" {
#   name = "concourse-${var.environment_name}-ecs-service"

#   assume_role_policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [{
#       Effect    = "Allow"
#       Action    = "sts:AssumeRole"
#       Principal = { Service = "ecs.amazonaws.com" }
#     }]
#   })
# }

# resource "aws_iam_role_policy_attachment" "ecs_service" {
#   role       = aws_iam_role.ecs_service.name
#   policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceRole"
# }

# Task execution role — allows ECS agent to pull secrets from Secrets Manager
resource "aws_iam_role" "ecs_task_execution" {
  name = "concourse-${var.environment_name}-task-execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "ecs_task_execution_secrets" {
  name = "postgres-secret-read"
  role = aws_iam_role.ecs_task_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = [var.postgres_master_secret_arn]
    }]
  })
}

# ALB
resource "aws_security_group" "concourse_public" {
  name        = "concourse-${var.environment_name}-alb"
  description = "Concourse ALB"
  vpc_id      = data.aws_vpc.concourse.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_tasks.id]
  }
}

resource "aws_security_group_rule" "ecs_tasks_from_alb" {
  type                     = "ingress"
  from_port                = 8080
  to_port                  = 8080
  protocol                 = "tcp"
  security_group_id        = aws_security_group.ecs_tasks.id
  source_security_group_id = aws_security_group.concourse_public.id
  description              = "Allow ALB to reach ECS tasks on 8080"
}

resource "aws_security_group_rule" "postgres_from_ecs_tasks" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = var.postgres_security_group_id
  source_security_group_id = aws_security_group.ecs_tasks.id
  description              = "Allow ECS tasks to reach PostgreSQL on 5432"
}

resource "random_id" "concourse_public" {
  byte_length = 4
}

resource "aws_lb" "concourse_public" {
  name               = "concourse-${var.environment_name}"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.concourse_public.id]
  subnets            = data.aws_subnets.public.ids
}

resource "aws_lb_target_group" "concourse_public" {
  name        = "concourse-${var.environment_name}-${random_id.concourse_public.hex}"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.concourse.id
  target_type = "ip"

  lifecycle {
    create_before_destroy = true
  }

  health_check {
    path                = "/api/v1/info"
    healthy_threshold   = 2
    unhealthy_threshold = 5
    interval            = 30
    timeout             = 10
  }
}

resource "random_id" "concourse_internal" {
  byte_length = 4
}

resource "aws_lb" "concourse_internal" {
  name               = "concourse-${var.environment_name}-internal"
  internal           = true
  load_balancer_type = "application"
  security_groups    = [aws_security_group.concourse_public.id]
  subnets            = data.aws_subnets.private.ids
}

resource "aws_lb_target_group" "concourse_internal" {
  name        = "concourse-${var.environment_name}-${random_id.concourse_internal.hex}"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.concourse.id
  target_type = "ip"

  lifecycle {
    create_before_destroy = true
  }

  health_check {
    path                = "/api/v1/info"
    healthy_threshold   = 2
    unhealthy_threshold = 5
    interval            = 30
    timeout             = 10
  }
}

resource "aws_acm_certificate" "concourse_public" {
  domain_name       = "concourse.danforge.net"
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_acm_certificate" "concourse_internal" {
  domain_name       = "concourse.int.danforge.net"
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "concourse_public_cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.concourse_public.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.public.zone_id
}

resource "aws_route53_record" "concourse_internal_cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.concourse_internal.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.public.zone_id
}

resource "aws_acm_certificate_validation" "concourse_public" {
  certificate_arn         = aws_acm_certificate.concourse_public.arn
  validation_record_fqdns = [for record in aws_route53_record.concourse_public_cert_validation : record.fqdn]
}

resource "aws_acm_certificate_validation" "concourse_internal" {
  certificate_arn         = aws_acm_certificate.concourse_internal.arn
  validation_record_fqdns = [for record in aws_route53_record.concourse_internal_cert_validation : record.fqdn]
}

resource "aws_route53_record" "concourse_public" {
  zone_id = data.aws_route53_zone.public.zone_id
  name    = "concourse.danforge.net"
  type    = "A"

  alias {
    name                   = aws_lb.concourse_public.dns_name
    zone_id                = aws_lb.concourse_public.zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "concourse_internal" {
  zone_id = data.aws_route53_zone.private.zone_id
  name    = "concourse.int.danforge.net"
  type    = "A"

  alias {
    name                   = aws_lb.concourse_internal.dns_name
    zone_id                = aws_lb.concourse_internal.zone_id
    evaluate_target_health = true
  }
}

resource "aws_lb_listener" "concourse_public_http" {
  load_balancer_arn = aws_lb.concourse_public.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_lb_listener" "concourse_public" {
  load_balancer_arn = aws_lb.concourse_public.arn
  port              = 443
  protocol          = "HTTPS"
  certificate_arn   = aws_acm_certificate_validation.concourse_public.certificate_arn
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "Forbidden"
      status_code  = "403"
    }
  }
}

resource "aws_lb_listener_rule" "concourse_public_well_known" {
  listener_arn = aws_lb_listener.concourse_public.arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.concourse_public.arn
  }

  condition {
    path_pattern {
      values = ["/.well-known/openid-configuration", "/.well-known/jwks.json"]
    }
  }

  condition {
    http_request_method {
      values = ["GET", "HEAD"]
    }
  }
}

resource "aws_lb_listener" "concourse_internal_http" {
  load_balancer_arn = aws_lb.concourse_internal.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_lb_listener" "concourse_internal" {
  load_balancer_arn = aws_lb.concourse_internal.arn
  port              = 443
  protocol          = "HTTPS"
  certificate_arn   = aws_acm_certificate_validation.concourse_internal.certificate_arn
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.concourse_internal.arn
  }
}

# CloudWatch log group for the Concourse task
resource "aws_cloudwatch_log_group" "concourse" {
  name              = "/ecs/concourse-${var.environment_name}"
  retention_in_days = 7
}

# Task definition
resource "aws_ecs_task_definition" "concourse" {
  family             = "concourse-${var.environment_name}"
  network_mode       = "awsvpc"
  execution_role_arn = aws_iam_role.ecs_task_execution.arn

  requires_compatibilities = ["EC2"]

  container_definitions = jsonencode([{
    name       = "concourse"
    image      = "concourse/concourse"
    essential  = true
    memory     = 4096
    cpu        = 1024
    privileged = true

    command = ["quickstart"]

    portMappings = [{
      containerPort = 8080
      hostPort      = 8080
      protocol      = "tcp"
    }]

    environment = [
      { name = "CONCOURSE_POSTGRES_HOST", value = var.postgres_host },
      { name = "CONCOURSE_POSTGRES_USER", value = "concourse_user" },
      { name = "CONCOURSE_POSTGRES_DATABASE", value = "concourse" },
      { name = "CONCOURSE_POSTGRES_SSLMODE", value = "require" },
      { name = "CONCOURSE_EXTERNAL_URL", value = "https://concourse.int.danforge.net" },
      { name = "CONCOURSE_OIDC_ISSUER_URL", value = "https://concourse.danforge.net" },
      { name = "CONCOURSE_ADD_LOCAL_USER", value = "test:test" },
      { name = "CONCOURSE_MAIN_TEAM_LOCAL_USER", value = "test" },
      { name = "CONCOURSE_WORKER_BAGGAGECLAIM_DRIVER", value = "overlay" },
      { name = "CONCOURSE_CLIENT_SECRET", value = "Y29uY291cnNlLXdlYgo=" },
      { name = "CONCOURSE_TSA_CLIENT_SECRET", value = "Y29uY291cnNlLXdvcmtlcgo=" },
      { name = "CONCOURSE_CLUSTER_NAME", value = var.environment_name },
      { name = "CONCOURSE_WORKER_CONTAINERD_DNS_SERVER", value = "8.8.8.8" },
      { name = "CONCOURSE_WORKER_RUNTIME", value = "containerd" },
      { name = "CONCOURSE_ENABLE_PIPELINE_INSTANCES", value = "true" },
      { name = "CONCOURSE_ENABLE_ACROSS_STEP", value = "true" },
      { name = "CONCOURSE_ENABLE_RESOURCE_CAUSALITY", value = "true" },
    ]

    secrets = [{
      name      = "CONCOURSE_POSTGRES_PASSWORD"
      valueFrom = "${var.postgres_master_secret_arn}:password::"
    }]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.concourse.name
        "awslogs-region"        = "eu-west-2"
        "awslogs-stream-prefix" = "concourse"
      }
    }
  }])
}

# First time provision may fail.
# See: https://github.com/hashicorp/terraform-provider-aws/issues/45693
resource "aws_ecs_service" "concourse" {
  name            = "concourse"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.concourse.arn
  desired_count   = 1

  capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.this.name
    weight            = 100
    base              = 1
  }

  ordered_placement_strategy {
    type  = "binpack"
    field = "cpu"
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.concourse_public.arn
    container_name   = "concourse"
    container_port   = 8080
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.concourse_internal.arn
    container_name   = "concourse"
    container_port   = 8080
  }

  network_configuration {
    subnets          = data.aws_subnets.private.ids
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }
}
