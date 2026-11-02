# ai_gpu

An on-demand AWS GPU for experimenting with ComfyUI and the open-weight Wan 2.2 TI2V-5B video model. This is a standalone personal project. The CDK package and stack tags retain the original internal name `ai_deploy`.

**Current state:** The trial deployment was torn down on 2026-11-01. No GPU, EBS volume, or CDK bootstrap stack from this project is running. Deploying again creates billable AWS resources.

## What it deploys

- One `g6e.xlarge` EC2 instance with an NVIDIA L40S GPU in `us-east-1`, using the account's default VPC.
- An encrypted 80 GiB gp3 root volume that keeps ComfyUI, model files, and outputs across stop/start cycles.
- A security group with no inbound rules and an EC2 role for AWS Systems Manager. ComfyUI listens only on the instance's `127.0.0.1:8188`.
- A first-boot installer that downloads and verifies the three files required by the [official Wan 2.2 5B ComfyUI workflow](https://docs.comfy.org/tutorials/video/wan/wan2_2).

There is no public ComfyUI port, SSH key, load balancer, Elastic IP, or NAT Gateway. The AMI is pinned to `ami-024b2999242b4b38d` in `us-east-1`; review it before redeploying later.

## Deploy

Requirements: Node.js 22+, AWS CLI, an AWS profile with permission to create the stack, and at least four vCPUs of EC2 G/VT on-demand quota in `us-east-1`.

```sh
npm ci
export AWS_PROFILE=your-profile
aws sts get-caller-identity
npx cdk bootstrap aws://ACCOUNT_ID/us-east-1
npm run synth
npx cdk deploy GpuHostStack
```

Replace `ACCOUNT_ID` with the account printed by `get-caller-identity`. Bootstrap is needed again because this project's bootstrap stack was deleted during teardown. Deployment launches a **running, billable GPU**. First boot installs ComfyUI and downloads about 18 GB of model files; allow time before connecting.

## Use and stop

Install the [AWS Session Manager plugin](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html) on your laptop. Then run:

```sh
AWS_PROFILE=your-profile ./scripts/connect-comfyui.sh
```

The script opens a private tunnel and launches `http://127.0.0.1:8188` when ComfyUI responds. Keep that terminal open during use. If local port 8188 is occupied, set `COMFYUI_LOCAL_PORT=18188` for the connection command. The full UI runs in your browser; inference runs on AWS.

When the ComfyUI queue is empty, stop the GPU:

```sh
AWS_PROFILE=your-profile ./scripts/stop-gpu.sh
AWS_PROFILE=your-profile ./scripts/start-gpu.sh  # next session
```

At the November 2026 check, the GPU cost about **$1.861/hour while running**, and the 80 GiB EBS volume cost about **$6.40/month even while stopped**. Check current AWS pricing before deploying. Stopping halts compute charges but does not reserve scarce GPU capacity; a later start can fail with `InsufficientInstanceCapacity`. The first trial did encounter that error on restart.

## Remove everything

Download any outputs you want to keep, then run:

```sh
AWS_PROFILE=your-profile ./scripts/teardown.sh
```

The script asks you to confirm, then deletes the EC2 instance, root volume, models, and outputs. It leaves the account's default VPC and CDK bootstrap stack. Delete a bootstrap stack only if no other CDK deployment uses it; its retained, versioned S3 asset bucket also needs cleanup.

## Troubleshooting

ComfyUI may take a few minutes to listen after a restart. If it does not start, open an AWS Systems Manager shell on the instance and check:

```sh
sudo systemctl status comfyui.service
sudo journalctl -u comfyui.service -n 100 --no-pager
sudo tail -n 100 /var/log/ai-deploy-setup.log
```

If first-boot installation failed, rerun `sudo /usr/local/sbin/ai-deploy-setup`. The root volume persists through stop/start, but a CDK update that replaces the instance can delete it. Back up outputs before changing the AMI or root block device.
