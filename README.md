# experiments-with-concourse

Experimenting with Concourse CI and hosting infrastructure.

## Objectives

| Objective                    | Achieved |
| ---------------------------- | -------- |
| GitHub-triggered pipeline.   | ✅       |
| AWS auth with OpenID Connect | ✅       |

### GitHub-triggered pipeline

Pipelines should trigger when GitHub repositories are updated. Very simple use case.
Relatively easy to implement, but a completely different experience to GitHub Actions
and others.

### AWS auth with OpenID Connect

I wanted to try using OpenID Connect to have repo-specific IAM Roles which could have
specialised permission sets for least-privilege access. I managed to get this working
with a bit of [script boilerplate](concourse/scripts/aws-oidc-auth.sh) in Concourse.

Alternative approaches might involve instance profiles with permission to assume
onwards IAM Roles but that might not be suitable depending on security requirements.

OpenID Connect requires a public JWKS endpoint on Concourse which exposes its public
keys, used by AWS to verify the JWT tokens. In the ECS/EC2 infrastructure patterns,
I achieved this by having two ALBs, one internet-facing and another private. The
internet-facing ALB only responded to the JWKS endpoints `/.well-known/openid-configuration`
and `/.well-known/jwks.json` with other requests returning HTTP 403 (Forbidden). This
scenario required Concourse to be aware of the URL difference which is possible using
environment variables `CONCOURSE_EXTERNAL_URL` and `CONCOURSE_OIDC_ISSUER_URL`. To
access the private ALB, I configured [AWS Client VPN with OpenTofu](https://www.themomentum.ai/blog/building-client-vpn-on-aws-with-terraform).

I have not replicated this in the EKS environment because it's built using an existing
Helm chart which will require extending to support this higher-security pattern.

## Hosting Platforms

| Platform                                    | Worked |
| ------------------------------------------- | ------ |
| ECS Managed Instances                       | ❌     |
| ECS with self-managed EC2 compute provider  | ✅     |
| EC2 ASG pets                                | ✅     |
| EKS managed nodes with Concourse Helm chart | ✅     |

### ECS Managed Instances

Concourse pipelines failed to start Docker containers because the underlying
kernel did not support user namespaces and cannot be modified.

### ECS with Self-Managed EC2 Compute Provider

Pipelines run successfully but additional work is required to handle worker
replacements and registration.

### EC2 ASG pets

Runs Concourse as systemd services, required custom Packer-built AMIs with
binaries baked in. Requires additional work to integrate with EC2 health
checks and worker replacements and registration.

### EKS managed nodes with Concourse Helm chart

Mostly worked out-of-the-box. EKS experience would be valuable. Would also
need extending to support HTTPS endpoints, custom domain names, etc.

## Notes

### Tofu state

Just using local state files for this experiment.

### Command Notes

1. Run Concourse: `docker compose up`

2. Install [fly CLI](http://localhost:8080/download-fly)

3. CLI auth: `fly -t tutorial login -c http://localhost:8080 -u test -p test`

4. List workers: `fly -t tutorial workers`

5. Register pipeline: `fly -t tutorial set-pipeline -p hello-world -c concourse/hello-world.yml`

6. Unpause new pipeline: `fly -t tutorial unpause-pipeline -p hello-world`

7. Run pipeline: `fly -t tutorial trigger-job --job hello-world/hello-world-job --watch`

### Recommended VS Code Extensions

- [Concourse CI Pipeline Editor](https://marketplace.visualstudio.com/items?itemName=vmware.vscode-concourse) (Requires Java)

### EC2/Packer Prep

```bash
# Get VPC ID
aws ec2 describe-vpcs --filters "Name=tag:Name,Values=concourse" \
  --query "Vpcs[0].VpcId" --output text --profile admin

# Get subnet ID
aws ec2 describe-subnets \
  --filters "Name=tag:Name,Values=concourse-public-*" \
  --query "Subnets[0].SubnetId" --output text --profile admin

cd packer
packer init web.pkr.hcl
packer init worker.pkr.hcl

AWS_PROFILE=admin AWS_DEFAULT_REGION=eu-west-2 packer build \
  -var "concourse_version=8.2.3" \
  -var "vpc_id=vpc-0b5a6a4d9f1ff42c5" \
  -var "subnet_id=subnet-02e17d796d820033b" \
  web.pkr.hcl


AWS_PROFILE=admin AWS_DEFAULT_REGION=eu-west-2 packer build \
  -var "concourse_version=8.2.3" \
  -var "vpc_id=vpc-0b5a6a4d9f1ff42c5" \
  -var "subnet_id=subnet-02e17d796d820033b" \
  worker.pkr.hcl
```

### EKS

```bash
aws eks update-kubeconfig --name concourse-prod --region eu-west-2 --profile admin
```

```bash
# Use gp3 as the default storage class
kubectl apply -f - <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp3
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
volumeBindingMode: WaitForFirstConsumer
EOF
```

```bash
# Secret generation
mkdir -p concourse-secrets && cd concourse-secrets

ssh-keygen -t rsa -b 4096 -f host-key -N '' -m PEM
ssh-keygen -t rsa -b 4096 -f worker-key -N '' -m PEM
ssh-keygen -t rsa -b 4096 -f session-signing-key -N '' -m PEM

rm session-signing-key.pub
mkdir web worker concourse

# Worker secrets
mv host-key.pub   worker/host-key-pub
mv worker-key.pub worker/worker-key-pub
mv worker-key     worker/worker-key

# Web secrets
mv session-signing-key web/session-signing-key
mv host-key            web/host-key
cp worker/worker-key-pub web/worker-key-pub

printf "%s:%s" "admin" "$(openssl rand -base64 18)" > web/local-users
cat web/local-users  # default login username/password

kubectl create secret generic concourse-worker    --from-file=worker/
kubectl create secret generic concourse-web       --from-file=web/
kubectl create secret generic concourse-concourse --from-file=concourse/
```

```bash
helm repo add concourse https://concourse-charts.storage.googleapis.com/

helm install concourse concourse/concourse \
  --set secrets.create=false \
  --set "concourse.web.auth.mainTeam.localUser=admin" \
  --set web.service.api.type=LoadBalancer \
  --set persistence.worker.storageClass=gp3

kubectl get svc concourse-web -w

helm upgrade concourse concourse/concourse \
  --reuse-values \
  --set "concourse.web.externalUrl=http://abc123.eu-west-2.elb.amazonaws.com:8080"
```
