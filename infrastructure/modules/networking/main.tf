module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "concourse"
  cidr = "10.0.0.0/16"

  azs              = ["eu-west-2a", "eu-west-2b", "eu-west-2c"]
  database_subnets = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]
  private_subnets  = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets   = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  create_database_subnet_route_table = true
  create_database_subnet_group       = true
  enable_nat_gateway                 = true
  enable_vpn_gateway                 = false
}

resource "aws_route53_zone" "private_zone" {
  name          = "int.danforge.net"
  force_destroy = true

  vpc {
    vpc_id = module.vpc.vpc_id
  }
}


