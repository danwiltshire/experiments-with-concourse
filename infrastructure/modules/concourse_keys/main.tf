################################################################################
# Key generation
#
# Concourse requires RSA keys in PEM (PKCS#1) format, equivalent to:
#   ssh-keygen -t rsa -b 4096 -m PEM -f <key>
#
# tls_private_key outputs:
#   private_key_pem     — PKCS#1 PEM (the private key file)
#   public_key_openssh  — OpenSSH authorised-keys format (used by TSA for
#                         CONCOURSE_TSA_AUTHORIZED_KEYS and
#                         CONCOURSE_TSA_PUBLIC_KEY)
################################################################################

resource "tls_private_key" "session_signing" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "tls_private_key" "tsa_host" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "tls_private_key" "worker" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

################################################################################
# Secrets Manager – private keys (web node)
################################################################################

resource "aws_secretsmanager_secret" "session_signing_key" {
  name        = "${var.label}/concourse/session-signing-key"
  description = "Concourse session signing private key."
}

resource "aws_secretsmanager_secret_version" "session_signing_key" {
  secret_id     = aws_secretsmanager_secret.session_signing_key.id
  secret_string = tls_private_key.session_signing.private_key_pem
}

resource "aws_secretsmanager_secret" "tsa_host_key" {
  name        = "${var.label}/concourse/tsa-host-key"
  description = "Concourse TSA host private key (web nodes)."
}

resource "aws_secretsmanager_secret_version" "tsa_host_key" {
  secret_id     = aws_secretsmanager_secret.tsa_host_key.id
  secret_string = tls_private_key.tsa_host.private_key_pem
}

################################################################################
# Secrets Manager – TSA host public key (worker nodes)
#
# Workers use this to verify the identity of the TSA host (CONCOURSE_TSA_PUBLIC_KEY).
################################################################################

resource "aws_secretsmanager_secret" "tsa_host_key_pub" {
  name        = "${var.label}/concourse/tsa-host-key-pub"
  description = "Concourse TSA host public key (worker nodes use to verify TSA identity)."
}

resource "aws_secretsmanager_secret_version" "tsa_host_key_pub" {
  secret_id     = aws_secretsmanager_secret.tsa_host_key_pub.id
  secret_string = tls_private_key.tsa_host.public_key_openssh
}

################################################################################
# Secrets Manager – worker private key (worker nodes)
################################################################################

resource "aws_secretsmanager_secret" "worker_key" {
  name        = "${var.label}/concourse/worker-key"
  description = "Concourse worker private key."
}

resource "aws_secretsmanager_secret_version" "worker_key" {
  secret_id     = aws_secretsmanager_secret.worker_key.id
  secret_string = tls_private_key.worker.private_key_pem
}

################################################################################
# Secrets Manager – worker public key (web node)
#
# Web nodes use this to authorise workers (CONCOURSE_TSA_AUTHORIZED_KEYS).
################################################################################

resource "aws_secretsmanager_secret" "worker_key_pub" {
  name        = "${var.label}/concourse/worker-key-pub"
  description = "Concourse worker public key (web nodes use to authorise workers)."
}

resource "aws_secretsmanager_secret_version" "worker_key_pub" {
  secret_id     = aws_secretsmanager_secret.worker_key_pub.id
  secret_string = tls_private_key.worker.public_key_openssh
}
