################################################################################
# Data Sources
################################################################################

data "aws_region" "current" {}

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

################################################################################
# Random IDs (for target group names, which must be unique on replacement)
################################################################################

resource "random_id" "concourse_public" {
  byte_length = 4
}

resource "random_id" "concourse_internal" {
  byte_length = 4
}

################################################################################
# IAM – Web instance role
################################################################################

resource "aws_iam_role" "web" {
  name = "concourse-${var.environment_name}-web"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachments_exclusive" "web" {
  role_name = aws_iam_role.web.name
  policy_arns = [
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
    "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy",
  ]
}

resource "aws_iam_role_policy" "web_secrets" {
  name = "concourse-web-secrets"
  role = aws_iam_role.web.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["secretsmanager:GetSecretValue"]
      Resource = [
        var.postgres_master_secret_arn,
        var.session_signing_key_secret_arn,
        var.tsa_host_key_secret_arn,
        var.worker_key_pub_secret_arn,
      ]
    }]
  })
}

resource "aws_iam_instance_profile" "web" {
  name = "concourse-${var.environment_name}-web"
  role = aws_iam_role.web.name
}

################################################################################
# IAM – Worker instance role
################################################################################

resource "aws_iam_role" "worker" {
  name = "concourse-${var.environment_name}-worker"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachments_exclusive" "worker" {
  role_name = aws_iam_role.worker.name
  policy_arns = [
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
    "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy",
  ]
}

resource "aws_iam_role_policy" "worker_secrets" {
  name = "concourse-worker-secrets"
  role = aws_iam_role.worker.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["secretsmanager:GetSecretValue"]
      Resource = [
        var.tsa_host_key_pub_secret_arn,
        var.worker_key_secret_arn,
      ]
    }]
  })
}

resource "aws_iam_instance_profile" "worker" {
  name = "concourse-${var.environment_name}-worker"
  role = aws_iam_role.worker.name
}

################################################################################
# Security Groups
################################################################################

# Shared by both public and internal ALBs
resource "aws_security_group" "alb" {
  name        = "concourse-${var.environment_name}-alb"
  description = "Concourse ALB (public and internal)"
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
    description     = "Forward to web instances"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.web.id]
  }
}

resource "aws_security_group" "web" {
  name        = "concourse-${var.environment_name}-web"
  description = "Concourse web nodes"
  vpc_id      = data.aws_vpc.concourse.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group_rule" "web_from_alb" {
  type                     = "ingress"
  from_port                = 8080
  to_port                  = 8080
  protocol                 = "tcp"
  security_group_id        = aws_security_group.web.id
  source_security_group_id = aws_security_group.alb.id
  description              = "Allow ALBs to reach web nodes on 8080"
}

resource "aws_security_group_rule" "web_tsa_from_workers" {
  type                     = "ingress"
  from_port                = 2222
  to_port                  = 2222
  protocol                 = "tcp"
  security_group_id        = aws_security_group.web.id
  source_security_group_id = aws_security_group.worker.id
  description              = "Allow workers to reach TSA on 2222"
}

resource "aws_security_group_rule" "web_tsa_from_nlb" {
  type                     = "ingress"
  from_port                = 2222
  to_port                  = 2222
  protocol                 = "tcp"
  security_group_id        = aws_security_group.web.id
  source_security_group_id = aws_security_group.tsa_nlb.id
  description              = "Allow TSA NLB health checks and forwarded traffic to reach web nodes on 2222"
}

resource "aws_security_group" "worker" {
  name        = "concourse-${var.environment_name}-worker"
  description = "Concourse worker nodes"
  vpc_id      = data.aws_vpc.concourse.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Allow web nodes (and thus TSA) to be reached from workers via the NLB.
# NLBs preserve source IP so the security group rule on web instances works.
resource "aws_security_group_rule" "postgres_from_web" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = var.postgres_security_group_id
  source_security_group_id = aws_security_group.web.id
  description              = "Allow web nodes to reach PostgreSQL on 5432"
}

################################################################################
# ACM Certificates
################################################################################

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

################################################################################
# Public ALB
################################################################################

resource "aws_lb" "concourse_public" {
  name               = "concourse-${var.environment_name}"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = data.aws_subnets.public.ids
}

resource "aws_lb_target_group" "concourse_public" {
  name        = "concourse-${var.environment_name}-${random_id.concourse_public.hex}"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.concourse.id
  target_type = "instance"

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

# Default action is 403 — only explicitly allowed paths are forwarded.
resource "aws_lb_listener" "concourse_public_https" {
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

# Only expose the OIDC well-known endpoints via the public ALB.
resource "aws_lb_listener_rule" "concourse_public_well_known" {
  listener_arn = aws_lb_listener.concourse_public_https.arn
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

################################################################################
# Internal ALB
################################################################################

resource "aws_lb" "concourse_internal" {
  name               = "concourse-${var.environment_name}-internal"
  internal           = true
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = data.aws_subnets.private.ids
}

resource "aws_lb_target_group" "concourse_internal" {
  name        = "concourse-${var.environment_name}-${random_id.concourse_internal.hex}"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.concourse.id
  target_type = "instance"

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

resource "aws_lb_listener" "concourse_internal_https" {
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

################################################################################
# Internal NLB – TSA (port 2222)
#
# ALBs only support HTTP/HTTPS. Workers connect to web nodes via TSA (TCP 2222),
# so a separate internal NLB is required. NLBs preserve source IP, so the
# security group rule on the web SG (allowing workers on 2222) still applies.
################################################################################

resource "aws_security_group" "tsa_nlb" {
  name        = "concourse-${var.environment_name}-tsa-nlb"
  description = "Concourse TSA NLB"
  vpc_id      = data.aws_vpc.concourse.id

  ingress {
    description     = "Accept worker connections to TSA"
    from_port       = 2222
    to_port         = 2222
    protocol        = "tcp"
    security_groups = [aws_security_group.worker.id]
  }

  egress {
    description     = "Forward to web instances on TSA port"
    from_port       = 2222
    to_port         = 2222
    protocol        = "tcp"
    security_groups = [aws_security_group.web.id]
  }
}

resource "aws_lb" "tsa" {
  name               = "concourse-${var.environment_name}-tsa"
  internal           = true
  load_balancer_type = "network"
  subnets            = data.aws_subnets.private.ids
  security_groups    = [aws_security_group.tsa_nlb.id]
}

resource "aws_lb_target_group" "tsa" {
  name        = "concourse-${var.environment_name}-tsa-${random_id.concourse_public.hex}"
  port        = 2222
  protocol    = "TCP"
  vpc_id      = data.aws_vpc.concourse.id
  target_type = "instance"

  health_check {
    protocol            = "TCP"
    port                = "2222"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 30
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_listener" "tsa" {
  load_balancer_arn = aws_lb.tsa.arn
  port              = 2222
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tsa.arn
  }
}

resource "aws_route53_record" "tsa" {
  zone_id = data.aws_route53_zone.private.zone_id
  name    = "tsa.int.danforge.net"
  type    = "A"

  alias {
    name                   = aws_lb.tsa.dns_name
    zone_id                = aws_lb.tsa.zone_id
    evaluate_target_health = true
  }
}

################################################################################
# CloudWatch Log Groups
################################################################################

resource "aws_cloudwatch_log_group" "web" {
  name              = "/concourse/${var.environment_name}/web"
  retention_in_days = 7
}

resource "aws_cloudwatch_log_group" "worker" {
  name              = "/concourse/${var.environment_name}/worker"
  retention_in_days = 7
}

################################################################################
# Launch Template – Web
################################################################################

resource "aws_launch_template" "web" {
  name_prefix            = "concourse-${var.environment_name}-web-"
  image_id               = var.web_ami_id
  instance_type          = var.web_instance_type
  update_default_version = true

  vpc_security_group_ids = [aws_security_group.web.id]

  iam_instance_profile {
    arn = aws_iam_instance_profile.web.arn
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
    set -euo pipefail
    IMDS_TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
    REGION=$(curl -s -H "X-aws-ec2-metadata-token: $IMDS_TOKEN" http://169.254.169.254/latest/meta-data/placement/region)

    # Fetch Concourse keys from Secrets Manager
    mkdir -p /usr/local/concourse/keys

    aws secretsmanager get-secret-value \
      --region "$REGION" \
      --secret-id "${var.session_signing_key_secret_arn}" \
      --query SecretString --output text \
      > /usr/local/concourse/keys/session_signing_key

    aws secretsmanager get-secret-value \
      --region "$REGION" \
      --secret-id "${var.tsa_host_key_secret_arn}" \
      --query SecretString --output text \
      > /usr/local/concourse/keys/tsa_host_key

    aws secretsmanager get-secret-value \
      --region "$REGION" \
      --secret-id "${var.worker_key_pub_secret_arn}" \
      --query SecretString --output text \
      > /usr/local/concourse/keys/worker_key.pub

    chmod 600 /usr/local/concourse/keys/session_signing_key
    chmod 600 /usr/local/concourse/keys/tsa_host_key
    chmod 644 /usr/local/concourse/keys/worker_key.pub

    # Extract postgres password from the RDS-managed JSON secret
    POSTGRES_PASSWORD=$(aws secretsmanager get-secret-value \
      --region "$REGION" \
      --secret-id "${var.postgres_master_secret_arn}" \
      --query SecretString --output text \
      | python3 -c "import sys, json; print(json.load(sys.stdin)['password'])")

    cat > /usr/local/concourse/web.env <<ENV_FILE
    PATH=/usr/local/concourse/bin
    CONCOURSE_CLUSTER_NAME=${var.concourse_cluster_name}
    CONCOURSE_EXTERNAL_URL=https://concourse.int.danforge.net
    CONCOURSE_OIDC_ISSUER_URL=https://concourse.danforge.net
    CONCOURSE_POSTGRES_HOST=${var.postgres_host}
    CONCOURSE_POSTGRES_USER=${var.concourse_postgres_user}
    CONCOURSE_POSTGRES_DATABASE=${var.concourse_postgres_database}
    CONCOURSE_POSTGRES_PASSWORD=$POSTGRES_PASSWORD
    CONCOURSE_POSTGRES_SSLMODE=require
    CONCOURSE_SESSION_SIGNING_KEY=/usr/local/concourse/keys/session_signing_key
    CONCOURSE_TSA_HOST_KEY=/usr/local/concourse/keys/tsa_host_key
    CONCOURSE_TSA_AUTHORIZED_KEYS=/usr/local/concourse/keys/worker_key.pub
    CONCOURSE_MAIN_TEAM_LOCAL_USER=${var.concourse_main_team_local_user}
    CONCOURSE_ADD_LOCAL_USER=${var.concourse_add_local_user}
    CONCOURSE_ENABLE_CACHE_STREAMED_VOLUMES=true
    CONCOURSE_ENABLE_PIPELINE_INSTANCES=true
    CONCOURSE_ENABLE_ACROSS_STEP=true
    CONCOURSE_ENABLE_RESOURCE_CAUSALITY=true
    ENV_FILE

    chmod 0440 /usr/local/concourse/web.env
    chown -R concourse:concourse /usr/local/concourse

    systemctl enable concourse-web
    systemctl start concourse-web
  EOT
  )

  lifecycle {
    create_before_destroy = true
  }
}

################################################################################
# Launch Template – Worker
################################################################################

resource "aws_launch_template" "worker" {
  name_prefix            = "concourse-${var.environment_name}-worker-"
  image_id               = var.worker_ami_id
  instance_type          = var.worker_instance_type
  update_default_version = true

  vpc_security_group_ids = [aws_security_group.worker.id]

  iam_instance_profile {
    arn = aws_iam_instance_profile.worker.arn
  }

  monitoring {
    enabled = true
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      # Workers store container layers and task caches on disk; allocate generously.
      volume_size = 100
      volume_type = "gp3"
    }
  }

  user_data = base64encode(<<-EOT
    #!/bin/bash
    set -euo pipefail
    IMDS_TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
    REGION=$(curl -s -H "X-aws-ec2-metadata-token: $IMDS_TOKEN" http://169.254.169.254/latest/meta-data/placement/region)
    INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $IMDS_TOKEN" http://169.254.169.254/latest/meta-data/instance-id)

    mkdir -p /usr/local/concourse/keys /opt/concourse

    aws secretsmanager get-secret-value \
      --region "$REGION" \
      --secret-id "${var.tsa_host_key_pub_secret_arn}" \
      --query SecretString --output text \
      > /usr/local/concourse/keys/tsa_host_key.pub

    aws secretsmanager get-secret-value \
      --region "$REGION" \
      --secret-id "${var.worker_key_secret_arn}" \
      --query SecretString --output text \
      > /usr/local/concourse/keys/worker_key

    chmod 644 /usr/local/concourse/keys/tsa_host_key.pub
    chmod 600 /usr/local/concourse/keys/worker_key

    cat > /usr/local/concourse/worker.env <<ENV_FILE
    PATH=/usr/local/concourse/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
    CONCOURSE_NAME=$INSTANCE_ID
    CONCOURSE_WORK_DIR=/opt/concourse
    CONCOURSE_TSA_HOST=tsa.int.danforge.net:2222
    CONCOURSE_TSA_PUBLIC_KEY=/usr/local/concourse/keys/tsa_host_key.pub
    CONCOURSE_TSA_WORKER_PRIVATE_KEY=/usr/local/concourse/keys/worker_key
    CONCOURSE_BAGGAGECLAIM_DRIVER=overlay
    CONCOURSE_WORKER_RUNTIME=containerd
    CONCOURSE_WORKER_CONTAINERD_DNS_SERVER=8.8.8.8
    ENV_FILE

    chmod 0440 /usr/local/concourse/worker.env

    systemctl enable concourse-worker
    systemctl start concourse-worker
  EOT
  )

  lifecycle {
    create_before_destroy = true
  }
}

################################################################################
# Auto Scaling Groups
################################################################################

resource "aws_autoscaling_group" "web" {
  name_prefix         = "concourse-${var.environment_name}-web-"
  min_size            = var.web_min_size
  max_size            = var.web_max_size
  desired_capacity    = var.web_desired_capacity
  vpc_zone_identifier = data.aws_subnets.private.ids

  # Register with all three target groups (public ALB, internal ALB, TSA NLB)
  target_group_arns = [
    aws_lb_target_group.concourse_public.arn,
    aws_lb_target_group.concourse_internal.arn,
    aws_lb_target_group.tsa.arn,
  ]

  launch_template {
    id = aws_launch_template.web.id
  }

  health_check_type         = "ELB"
  health_check_grace_period = 120

  lifecycle {
    create_before_destroy = true
  }

  tag {
    key                 = "Name"
    value               = "concourse-${var.environment_name}-web"
    propagate_at_launch = true
  }
}

resource "aws_autoscaling_group" "worker" {
  name_prefix         = "concourse-${var.environment_name}-worker-"
  min_size            = var.worker_min_size
  max_size            = var.worker_max_size
  desired_capacity    = var.worker_desired_capacity
  vpc_zone_identifier = data.aws_subnets.private.ids

  launch_template {
    id = aws_launch_template.worker.id
  }

  health_check_type         = "EC2"
  health_check_grace_period = 180

  lifecycle {
    create_before_destroy = true
  }

  tag {
    key                 = "Name"
    value               = "concourse-${var.environment_name}-worker"
    propagate_at_launch = true
  }
}
