output "vpn_endpoint_dns_name" {
  description = "DNS name of the Client VPN endpoint (use as the remote address in client configs)."
  value       = aws_ec2_client_vpn_endpoint.vpn.dns_name
}

output "vpn_config_secret_arn" {
  description = "ARN of the Secrets Manager secret containing the OpenVPN client configuration."
  value       = aws_secretsmanager_secret.vpn_config.arn
}
