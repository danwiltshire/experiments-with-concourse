#!/usr/bin/env bash
# Shared Packer provisioner: installs the Concourse binary and configures
# the systemd unit for either the 'web' or 'worker' role.
#
# Expected env vars (set by Packer):
#   CONCOURSE_VERSION  e.g. "7.11.2"
#   CONCOURSE_ROLE     "web" or "worker"

set -euo pipefail

SYSTEM_ARCH=$(case "$(uname -m)" in
  x86_64)          echo amd64 ;;
  aarch64|arm64)   echo arm64 ;;
  *)               uname -m   ;;
esac)

CONCOURSE_URL="https://github.com/concourse/concourse/releases/download/v${CONCOURSE_VERSION}/concourse-${CONCOURSE_VERSION}-linux-${SYSTEM_ARCH}.tgz"

echo "==> Downloading Concourse ${CONCOURSE_VERSION} (${SYSTEM_ARCH})"
curl -fsSL "$CONCOURSE_URL" | tar xzf - -C /usr/local/

echo "==> Adding /usr/local/concourse/bin to system PATH"
echo 'PATH=/usr/local/concourse/bin:$PATH' > /etc/profile.d/concourse.sh

if [[ "$CONCOURSE_ROLE" == "web" ]]; then
  echo "==> Configuring web role"

  # Create the dedicated system user the web service runs as
  groupadd --system concourse
  useradd \
    --system \
    --gid concourse \
    --no-create-home \
    --shell /sbin/nologin \
    --comment "concourse web" \
    concourse

  mkdir -p /usr/local/concourse/keys
  chown -R concourse:concourse /usr/local/concourse

  # Install the systemd unit (uploaded by the Packer file provisioner)
  mv /tmp/concourse-web.service /etc/systemd/system/concourse-web.service

elif [[ "$CONCOURSE_ROLE" == "worker" ]]; then
  echo "==> Configuring worker role"

  # Workers run as root; create the work directory for runtime artifacts
  mkdir -p /opt/concourse
  mkdir -p /usr/local/concourse/keys

  # Enable user namespaces required by containerd workers
  echo "user.max_user_namespaces=15000" > /etc/sysctl.d/99-user-ns.conf

  # Install the systemd unit (uploaded by the Packer file provisioner)
  mv /tmp/concourse-worker.service /etc/systemd/system/concourse-worker.service

else
  echo "ERROR: CONCOURSE_ROLE must be 'web' or 'worker', got '${CONCOURSE_ROLE}'" >&2
  exit 1
fi

echo "==> Reloading systemd"
systemctl daemon-reload
