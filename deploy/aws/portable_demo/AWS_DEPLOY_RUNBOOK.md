# AWS Deploy Runbook (VSS Blueprint)

This runbook captures the working path for repeatable AWS demo deploys.

## 1) Prereqs (WSL)

- AWS CLI profile configured (example: `vss-terraform`)
- Terraform in `aws_vss/`
- Packer in `deploy/aws/portable_demo/`

Recommended shell exports:

```bash
export AWS_PROFILE=vss-terraform
export AWS_REGION=us-west-1
```

## 2) Build/Refresh GPU AMI (Packer)

From WSL:

```bash
cd /home/steve/video-search-and-summarization/deploy/aws/portable_demo
cp variables.pkrvars.hcl.example variables.pkrvars.hcl
# edit subnet_id / vpc_id / region as needed
packer init .
packer validate -var-file=variables.pkrvars.hcl .
packer build -var-file=variables.pkrvars.hcl .
```

Record AMI ID from output, e.g.:
- `us-west-1: ami-xxxxxxxxxxxxxxxxx`

## 3) Deploy Instance (Terraform)

Update AMI in:
- `/home/steve/video-search-and-summarization/aws_vss/terraform.tfvars`

Example:

```hcl
ami_id = "ami-xxxxxxxxxxxxxxxxx"
```

Then:

```bash
cd /home/steve/video-search-and-summarization/aws_vss
terraform plan
terraform apply
```

## 4) Connect + Verify Base Health

```bash
ssh -i /home/steve/homelab ubuntu@<AWS_PUBLIC_IP>
cloud-init status --wait
nvidia-smi
docker --version
docker compose version
ls -la /home/ubuntu/vssfork
git -C /home/ubuntu/vssfork branch --show-current
```

## 5) Copy `.env` From WSL To EC2

From WSL:

```bash
scp -i /home/steve/homelab /home/steve/video-search-and-summarization/deploy/docker/remote_vlm_deployment/.env \
ubuntu@<AWS_PUBLIC_IP>:/home/ubuntu/vssfork/deploy/docker/remote_vlm_deployment/.env
```

## 6) Fix `.env` on EC2

On EC2:

```bash
cd /home/ubuntu/vssfork/deploy/docker/remote_vlm_deployment
sed -i 's#/home/steve/video-search-and-summarization#/home/ubuntu/vssfork#g' .env
```

Set stable startup settings:

```bash
grep -q '^VIA_NUM_VLM_PROCS=' .env && sed -i 's/^VIA_NUM_VLM_PROCS=.*/VIA_NUM_VLM_PROCS=1/' .env || echo 'VIA_NUM_VLM_PROCS=1' >> .env
grep -q '^EMBEDDING_PARALLEL_COUNT=' .env && sed -i 's/^EMBEDDING_PARALLEL_COUNT=.*/EMBEDDING_PARALLEL_COUNT=1/' .env || echo 'EMBEDDING_PARALLEL_COUNT=1' >> .env
```

If Arango auth is not used, set explicit empty values:

```bash
grep -q '^ARANGO_DB_USERNAME=' .env && sed -i 's/^ARANGO_DB_USERNAME=.*/ARANGO_DB_USERNAME=/' .env || echo 'ARANGO_DB_USERNAME=' >> .env
grep -q '^ARANGO_DB_PASSWORD=' .env && sed -i 's/^ARANGO_DB_PASSWORD=.*/ARANGO_DB_PASSWORD=/' .env || echo 'ARANGO_DB_PASSWORD=' >> .env
```

## 7) Start Stack

```bash
docker compose up -d
docker compose ps
docker compose logs -f via-server
```

UI:
- `http://<AWS_PUBLIC_IP>:9100`

Backend health:

```bash
curl -sS http://127.0.0.1:8100/health/ready
```

## 8) Troubleshooting

If startup seems stuck:

```bash
docker compose logs --tail 300 via-server
docker compose ps
```

If host becomes unresponsive:
- Use AWS Console `Stop` then `Start` (more effective than reboot for hard stalls).

## 9) Recommended Instance Size

- `g4dn.2xlarge` minimum for better stability (8 vCPU / 32 GiB RAM / 1x T4).
- `g4dn.xlarge` works but is more likely to feel stalled during first cold startup.

## 10) Teardown

From WSL:

```bash
cd /home/steve/video-search-and-summarization/aws_vss
terraform destroy
```

## 11) Documentation Reminder

After final validation, commit:
- IAM policy JSON used for Terraform + Packer
- `deploy/aws/portable_demo/*`
- `aws_vss/*` changes
