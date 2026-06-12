variable "cluster_name" {
  type        = string
  description = "Name of the EKS cluster."
}

variable "vpc_id" {
  type        = string
  description = "ID of the VPC to deploy the EKS cluster into."
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "IDs of the private subnets for EKS nodes and control plane ENIs."
}
