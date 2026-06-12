locals {
  default_tags = {
    app  = "experiments-with-concourse"
    env  = var.environment_name
    repo = "https://github.com/danwiltshire/experiments-with-concourse"
  }
}

provider "aws" {
  profile = "admin"
  region  = "eu-west-2"
  alias   = "prod_eu_west_2"

  default_tags {
    tags = local.default_tags
  }
}
