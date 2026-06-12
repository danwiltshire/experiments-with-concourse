variable "vpc_id" {
  type        = string
  description = "ID of the VPC to attach the Client VPN endpoint to."
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR block of the VPC. The VPC DNS resolver (CIDR base +2) is inferred from this and used as the VPN DNS server. Also used as the authorisation target network."
}

variable "subnet_ids" {
  type        = list(string)
  description = "List of subnet IDs to associate with the Client VPN endpoint."
}

variable "label" {
  type        = string
  description = "Label used as a prefix for resource names (e.g. log group, security group)."
  default     = "vpn"
}

variable "log_retention_days" {
  type        = number
  description = "Retention period in days for the VPN connection CloudWatch log group."
  default     = 2192 # 6 years
}

variable "vpn_domain" {
  type        = string
  description = "DNS name used as the VPN server certificate common name and in the generated client config."
  default     = "vpn.danforge.net"
}

variable "organization_name" {
  type        = string
  description = "Organisation name embedded in TLS certificate subjects."
  default     = "concourse"
}

variable "client_cidr_block" {
  type        = string
  description = "CIDR block assigned to VPN clients. Must not overlap with the VPC CIDR."
  default     = "172.16.0.0/22"
}

variable "split_tunnel" {
  type        = bool
  description = "When true, only traffic destined for the VPC is routed through the VPN."
  default     = true
}

variable "allowed_cidr_blocks" {
  type        = list(string)
  description = "Source CIDR blocks permitted to connect to the VPN endpoint on 443/UDP."
  default     = ["0.0.0.0/0"]
}

variable "certificate_validity_period_hours" {
  type        = number
  description = "Validity period in hours for the VPN server and client TLS certificates."
  default     = 8760 # 1 year
}

variable "session_timeout_hours" {
  type        = number
  description = "Maximum VPN session duration in hours."
  default     = 8
}
