#!/usr/bin/env bash
set -euo pipefail

AWS_REGION="${AWS_DEFAULT_REGION:-us-east-1}"
KEY_PEM_PATH="./resume-demo-key.pem"
INSTANCE_ID="$1" # optional: pass instance-id or discover by tag
TAG_NAME="${TAG_NAME:-resume-parser-demo}"

if [ -z "${INSTANCE_ID:-}" ]; then
  INSTANCE_ID=$(aws ec2 describe-instances --region "$AWS_REGION" --filters "Name=tag:Name,Values=$TAG_NAME" "Name=instance-state-name,Values=running" --query 'Reservations[0].Instances[0].InstanceId' --output text)
fi

PUBLIC_IP=$(aws ec2 describe-instances --region "$AWS_REGION" --instance-ids "$INSTANCE_ID" --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
echo "Instance $INSTANCE_ID at $PUBLIC_IP"

# copy repo to EC2 and run deploy steps (example uses ubuntu user)
scp -o StrictHostKeyChecking=no -i "$KEY_PEM_PATH" -r ../ FINAL_PROJECT ubuntu@"$PUBLIC_IP":/home/ubuntu/
ssh -o StrictHostKeyChecking=no -i "$KEY_PEM_PATH" ubuntu@"$PUBLIC_IP" <<'SSH'
set -ex
cd /home/ubuntu/FINAL_PROJECT/api || cd /home/ubuntu/Vikas/ITMO_444_544_Fall2025/FINAL_PROJECT/api
python3 -m venv ../venv
source ../venv/bin/activate
pip install --upgrade pip
if [ -f requirements.txt ]; then pip install -r requirements.txt; fi
# start gunicorn systemd unit if present
sudo systemctl daemon-reload
sudo systemctl enable resume-parser || true
sudo systemctl start resume-parser || true
sudo systemctl restart nginx || true
SSH

echo "Deploy finished. Visit http://$PUBLIC_IP"
