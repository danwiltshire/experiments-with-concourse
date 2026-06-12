module "networking" {
  source = "../../modules/networking"

  providers = {
    aws = aws.prod_eu_west_2
  }
}

# module "vpn" {
#   source = "../../modules/vpn"

#   providers = {
#     aws = aws.prod_eu_west_2
#   }

#   label      = "danforge"
#   vpc_id     = module.networking.vpc_id
#   vpc_cidr   = module.networking.vpc_cidr_block
#   subnet_ids = module.networking.private_subnet_ids
# }
