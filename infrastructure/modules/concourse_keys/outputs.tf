output "session_signing_key_secret_arn" {
  description = "ARN of the Secrets Manager secret containing the session signing private key."
  value       = aws_secretsmanager_secret.session_signing_key.arn
}

output "tsa_host_key_secret_arn" {
  description = "ARN of the Secrets Manager secret containing the TSA host private key."
  value       = aws_secretsmanager_secret.tsa_host_key.arn
}

output "tsa_host_key_pub_secret_arn" {
  description = "ARN of the Secrets Manager secret containing the TSA host public key."
  value       = aws_secretsmanager_secret.tsa_host_key_pub.arn
}

output "worker_key_secret_arn" {
  description = "ARN of the Secrets Manager secret containing the worker private key."
  value       = aws_secretsmanager_secret.worker_key.arn
}

output "worker_key_pub_secret_arn" {
  description = "ARN of the Secrets Manager secret containing the worker public key."
  value       = aws_secretsmanager_secret.worker_key_pub.arn
}
