# AWS Demo Automation (Packer + user_data)

This folder gives you:
- A reusable GPU-ready AMI (`packer.pkr.hcl`)
- A minimal launch bootstrap for repo clone and startup prep (`user_data.sh`)

## 1) Build the AMI once with Packer

```bash
cd deploy/aws/portable_demo
cp variables.pkrvars.hcl.example variables.pkrvars.hcl
# edit variables.pkrvars.hcl with your subnet/vpc
packer init .
packer validate -var-file=variables.pkrvars.hcl .
packer build -var-file=variables.pkrvars.hcl .
```

Save the AMI ID from build output for Terraform.

## 2) Use AMI + user_data in Terraform

In your `aws_instance`:

```hcl
ami           = "ami-xxxxxxxxxxxxxxxxx" # packer output
instance_type = "g4dn.xlarge"
user_data     = file("${path.module}/user_data.sh")
```

The script has sane defaults:
- `REPO_URL=https://github.com/slade208/vssfork.git`
- `REPO_BRANCH=steve/cv-overlay-portable`
- `REPO_DIR=/home/ubuntu/vssfork`

If you want different values, edit `user_data.sh` before `terraform apply`.

## 3) Post-launch manual step (intentional)

On the instance:

```bash
cd /home/ubuntu/vssfork/deploy/docker/remote_vlm_deployment
# copy your protected .env into .env
sed -i 's#/home/steve/video-search-and-summarization#/home/ubuntu/vssfork#g' .env
docker compose up -d
```

## Notes

- First cold start is still slower due to model downloads and TensorRT engine build.
- The goal here is reducing OS/bootstrap friction to near-zero for repeated demo apply/destroy cycles.
