variable "environment_name" {
  type        = string
  description = "Environment name used in resource names."
}

################################################################################
# Packer AMIs
################################################################################

variable "web_ami_id" {
  type        = string
  description = "AMI ID for the Concourse web node, built by Packer."
}

variable "worker_ami_id" {
  type        = string
  description = "AMI ID for the Concourse worker node, built by Packer."
}

################################################################################
# Instance sizing
################################################################################

variable "web_instance_type" {
  type        = string
  description = "EC2 instance type for web nodes."
  default     = "t3.medium"
}

variable "worker_instance_type" {
  type        = string
  description = "EC2 instance type for worker nodes."
  default     = "t3.large"
}

variable "web_min_size" {
  type    = number
  default = 1
}

variable "web_max_size" {
  type    = number
  default = 3
}

variable "web_desired_capacity" {
  type    = number
  default = 1
}

variable "worker_min_size" {
  type    = number
  default = 1
}

variable "worker_max_size" {
  type    = number
  default = 5
}

variable "worker_desired_capacity" {
  type    = number
  default = 1
}

################################################################################
# Database
################################################################################

variable "postgres_host" {
  type        = string
  description = "Hostname of the Concourse PostgreSQL instance."
}

variable "postgres_master_secret_arn" {
  type        = string
  description = "ARN of the RDS-managed Secrets Manager secret containing the master DB credentials (JSON with 'password' key)."
}

variable "postgres_security_group_id" {
  type        = string
  description = "Security group ID attached to the PostgreSQL instance."
}

################################################################################
# Concourse keys (stored in Secrets Manager)
################################################################################

variable "session_signing_key_secret_arn" {
  type        = string
  description = "Secrets Manager ARN for the Concourse session signing private key."
}

variable "tsa_host_key_secret_arn" {
  type        = string
  description = "Secrets Manager ARN for the TSA host private key (web nodes)."
}

variable "tsa_host_key_pub_secret_arn" {
  type        = string
  description = "Secrets Manager ARN for the TSA host public key (worker nodes)."
}

variable "worker_key_secret_arn" {
  type        = string
  description = "Secrets Manager ARN for the worker private key."
}

variable "worker_key_pub_secret_arn" {
  type        = string
  description = "Secrets Manager ARN for the worker public key (authorised by web)."
}

################################################################################
# Concourse config
################################################################################

variable "concourse_cluster_name" {
  type    = string
  default = "concourse"
}

variable "concourse_postgres_user" {
  type    = string
  default = "concourse_user"
}

variable "concourse_postgres_database" {
  type    = string
  default = "concourse"
}

variable "concourse_add_local_user" {
  type        = string
  description = "Local user in user:password format, e.g. admin:changeme."
  default     = "admin:admin"
}

variable "concourse_main_team_local_user" {
  type    = string
  default = "admin"
}
