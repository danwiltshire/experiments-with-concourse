data "aws_vpc" "concourse" {
  provider = aws.prod_eu_west_2

  filter {
    name   = "tag:Name"
    values = ["concourse"]
  }
}

data "aws_subnets" "private" {
  provider = aws.prod_eu_west_2

  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.concourse.id]
  }

  filter {
    name   = "tag:Name"
    values = ["concourse-private-*"]
  }
}

module "compute_eks" {
  source = "../../modules/compute_eks"

  providers = {
    aws = aws.prod_eu_west_2
  }

  cluster_name       = "concourse-${var.environment_name}"
  vpc_id             = data.aws_vpc.concourse.id
  private_subnet_ids = data.aws_subnets.private.ids
}

# Experiments from other infrastructure patterns.

# module "storage" {
#   source = "../../modules/storage"

#   providers = {
#     aws = aws.prod_eu_west_2
#   }

#   label                = "concourse-${var.environment_name}"
#   vpc_id               = data.aws_vpc.concourse.id
#   db_subnet_group_name = "concourse"
# }

# module "concourse_keys" {
#   source = "../../modules/concourse_keys"

#   providers = {
#     aws = aws.prod_eu_west_2
#   }

#   label = var.environment_name
# }

# module "compute_ec2" {
#   source = "../../modules/compute_ec2"

#   providers = {
#     aws = aws.prod_eu_west_2
#   }

#   environment_name           = var.environment_name
#   postgres_host              = module.storage.postgres_host
#   postgres_master_secret_arn = module.storage.postgres_master_secret_arn
#   postgres_security_group_id = module.storage.postgres_security_group_id

#   web_ami_id    = "ami-031843653ca1e7757"
#   worker_ami_id = "ami-0ea277a4bda78c6b4"

#   session_signing_key_secret_arn = module.concourse_keys.session_signing_key_secret_arn
#   tsa_host_key_secret_arn        = module.concourse_keys.tsa_host_key_secret_arn
#   tsa_host_key_pub_secret_arn    = module.concourse_keys.tsa_host_key_pub_secret_arn
#   worker_key_secret_arn          = module.concourse_keys.worker_key_secret_arn
#   worker_key_pub_secret_arn      = module.concourse_keys.worker_key_pub_secret_arn
# }

# module "openid_connect_provider" {
#   source = "../../modules/openid_connect_provider"

#   providers = {
#     aws = aws.prod_eu_west_2
#   }
# }
