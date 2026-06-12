variable "label" {
  type        = string
  description = "Label used as a prefix for resource names (e.g. log group, security group)."
  default     = "storage"
}

variable "vpc_id" {
  type        = string
  description = "The VPC ID to associate the RDS security group with."
}

variable "db_subnet_group_name" {
  type        = string
  description = "The database subnet group name."
}
