resource "aws_iam_role" "this" {
  name = var.concourse_pipeline_name
  path = "/${var.label}/"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "sts:AssumeRoleWithWebIdentity"
        Principal = {
          Federated = var.openid_connect_provider_arn
        }
        Condition = {
          StringEquals = {
            "${var.concourse_domain_name}:aud" = "sts.amazonaws.com"
            "${var.concourse_domain_name}:sub" = "${var.concourse_team}/${var.concourse_pipeline_name}"
          }
        }
      }
    ]
  })
}
