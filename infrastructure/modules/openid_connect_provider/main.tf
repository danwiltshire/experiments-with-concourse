resource "aws_iam_openid_connect_provider" "this" {
  url = var.concourse_url

  client_id_list = [
    "sts.amazonaws.com",
  ]
}
