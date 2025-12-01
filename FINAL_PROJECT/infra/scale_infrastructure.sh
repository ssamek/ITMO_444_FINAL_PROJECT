#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
if [ ! -f "./config.sh" ]; then echo "Missing config.sh"; exit 1; fi
source ./config.sh
source ./cloudwatch_utils.sh

log_to_cw "Scaling infrastructure: launching additional EC2 instance..."

# Expect vpc_id.txt, sg_id.txt exist
if [ -f vpc_id.txt ]; then VPC_ID=$(cat vpc_id.txt); else echo "vpc_id.txt missing"; exit 1; fi
if [ -f sg_id.txt ]; then SG_ID=$(cat sg_id.txt); else echo "sg_id.txt missing"; exit 1; fi

# pick first subnet in VPC
SUBNET_ID=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --region "$REGION" --query 'Subnets[0].SubnetId' --output text)
if [ -z "$SUBNET_ID" ] || [ "$SUBNET_ID" = "None" ]; then echo "No subnet found in VPC $VPC_ID"; exit 1; fi

read -r -d '' USER_DATA <<'EOF' || true
#!/bin/bash
set -e
apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get install -y python3-pip git nginx
# minimal bootstrap identical to create script; clone and start the app
if [ ! -d /home/ubuntu/resume-app-source ]; then
  sudo -u ubuntu git clone https://github.com/your-username/Vikas.git /home/ubuntu/resume-app-source || true
else
  cd /home/ubuntu/resume-app-source && sudo -u ubuntu git pull || true
fi
cp -r /home/ubuntu/resume-app-source/api /home/ubuntu/resume-app
cp -r /home/ubuntu/resume-app-source/frontend /home/ubuntu/resume-app
cd /home/ubuntu/resume-app/api || exit 0
pip3 install -r requirements.txt || true
sudo -u ubuntu nohup gunicorn -w 2 -b 0.0.0.0:5000 app:app --chdir /home/ubuntu/resume-app/api > /var/log/resume_app_gunicorn.log 2>&1 &
EOF

INSTANCE_ID=$(aws ec2 run-instances \
  --image-id "$AMI_ID" \
  --instance-type "$INSTANCE_TYPE" \
  --key-name "$KEY_NAME" \
  --security-group-ids "$SG_ID" \
  --subnet-id "$SUBNET_ID" \
  --associate-public-ip-address \
  --user-data "$USER_DATA" \
  --region "$REGION" \
  --tag-specifications "ResourceType=instance,Tags=[{Key=${PROJECT_TAG_KEY},Value=${PROJECT_TAG_VALUE}}]" \
  --query "Instances[0].InstanceId" --output text)

aws ec2 wait instance-running --instance-ids "$INSTANCE_ID" --region "$REGION"
PUBLIC_IP=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" --region "$REGION" --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)

echo "$INSTANCE_ID" >> instance_id.txt
echo "$PUBLIC_IP" >> instance_ip.txt

log_to_cw "Launched additional instance: $INSTANCE_ID ($PUBLIC_IP)"
send_cw_metric 1
