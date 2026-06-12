variable "label" {
  type        = string
  description = "Label used as a prefix for resource names (e.g. log group, security group)."
  default     = "oidc"
}

variable "concourse_url" {
  type        = string
  description = "URL of the public Concourse endpoint."
}

variable "concourse_team" {
  type        = string
  description = "The Concourse team name."
  default     = "main"
}

variable "concourse_pipeline_name" {
  type        = string
  description = "The pipeline name."
}

variable "concourse_domain_name" {
  type        = string
  description = "Domain of the public Concourse endpoint."
}

variable "role_name" {
  type        = string
  description = "The IAM Role name."
}

variable "openid_connect_provider_arn" {
  type        = string
  description = "The ARN of the OpenID Connect provider for Concourse."
}
