#!/usr/bin/env bash

# Exchanges a Concourse OIDC token for temporary AWS credentials via
# AssumeRoleWithWebIdentity and exports them into the current shell environment.
#
# Required env vars:
#   aws_role_arn       - IAM role to assume (must trust your Concourse OIDC provider)
#   aws_oidc_token     - The OIDC JWT from Concourse var_sources idtoken, e.g. ((awstoken:token))
#
# Optional env vars:
#   aws_role_duration  - Session duration in seconds (default: 3600)
#   aws_role_session   - Session name (default: concourse-task)

set -euo pipefail

export AWS_PAGER=""

if [[ -z "${aws_role_arn:-}" ]]; then
    echo "aws_role_arn not provided. Please provide an IAM role ARN to assume." >&2
    exit 1
fi

if [[ -z "${aws_oidc_token:-}" ]]; then
    echo "aws_oidc_token not provided. Pass the Concourse idtoken value as this env var." >&2
    exit 1
fi

read -r AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN < <(
    aws sts assume-role-with-web-identity \
        --role-arn "${aws_role_arn}" \
        --role-session-name "${aws_role_session:-concourse-task}" \
        --web-identity-token "${aws_oidc_token}" \
        --duration-seconds "${aws_role_duration:-3600}" \
        --query "Credentials.[AccessKeyId,SecretAccessKey,SessionToken]" \
        --output text
)

export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
