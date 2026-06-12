resource "random_id" "suffix" {
  byte_length = 4
}

resource "aws_security_group" "postgres" {
  name        = "${var.label}-rds-${random_id.suffix.hex}"
  description = "PostgreSQL access for Concourse"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    # Fix dependent ENI error if the SG needs replacement.
    create_before_destroy = true
  }
}

resource "aws_db_instance" "this" {
  allocated_storage = 10
  db_name           = "concourse"
  identifier        = "${var.label}-${random_id.suffix.hex}"
  storage_encrypted = true
  engine            = "postgres"
  # aws rds describe-db-engine-versions --engine postgres --query 'DBEngineVersions[].EngineVersion' --output table
  engine_version              = "17.10"
  instance_class              = "db.t3.small"
  manage_master_user_password = true
  skip_final_snapshot         = true
  auto_minor_version_upgrade  = false
  username                    = "concourse_user"
  parameter_group_name        = "default.postgres17"
  db_subnet_group_name        = var.db_subnet_group_name
  publicly_accessible         = false
  vpc_security_group_ids      = [aws_security_group.postgres.id]
}
