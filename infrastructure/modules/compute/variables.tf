variable "environment_name" {
  type = string
}

variable "postgres_host" {
  type        = string
  description = "Hostname of the Concourse PostgreSQL instance"
}

variable "postgres_master_secret_arn" {
  type        = string
  description = "ARN of the Secrets Manager secret containing the RDS master user credentials"
}

variable "postgres_security_group_id" {
  type        = string
  description = "Security group ID attached to the PostgreSQL instance"
}
