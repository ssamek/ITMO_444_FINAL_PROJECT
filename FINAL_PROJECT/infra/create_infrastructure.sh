#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
source "$DIR/config.txt"

echo "Creating S3 bucket: $S3_BUCKET_NAME"
aws s3api create-bucket --bucket "$S3_BUCKET_NAME" --region "$AWS_REGION" \
  --create-bucket-configuration LocationConstraint="$AWS_REGION" || echo "bucket may already exist"

echo "Creating key pair (if not exists)"
if ! aws ec2 describe-key-pairs --region "$AWS_REGION" --key-names "$KEY_NAME" >/dev/null 2>&1; then
  aws ec2 create-key-pair --key-name "$KEY_NAME" --query 'KeyMaterial' --output text > "$KEY_NAME.pem"
  chmod 400 "$KEY_NAME.pem"
  echo "Saved $KEY_NAME.pem"
else
  echo "Key pair exists"
fi

echo "Creating security group"
SG_JSON=$(aws ec2 create-security-group \
  --group-name "${EC2_INSTANCE_NAME}-sg" \
  --description "security group for resume parser" \
  --vpc-id $(aws ec2 describe-vpcs --query "Vpcs[0].VpcId" --output text) --region "$AWS_REGION" 2>/dev/null || true)

# allow SSH and HTTP/5000
SG_ID=$(aws ec2 describe-security-groups --filters Name=group-name,Values="${EC2_INSTANCE_NAME}-sg" --query "SecurityGroups[0].GroupId" --output text --region "$AWS_REGION")
if [ -z "$SG_ID" ] || [ "$SG_ID" = "None" ]; then
  # fallback: assume default SG
  SG_ID=$(aws ec2 describe-security-groups --filters Name=group-name,Values="default" --query "SecurityGroups[0].GroupId" --output text --region "$AWS_REGION")
fi

aws ec2 authorize-security-group-ingress --group-id "$SG_ID" --protocol tcp --port 22 --cidr "$SSH_CIDR" --region "$AWS_REGION" || true
aws ec2 authorize-security-group-ingress --group-id "$SG_ID" --protocol tcp --port 5000 --cidr 0.0.0.0/0 --region "$AWS_REGION" || true

echo "Creating IAM role for EC2 to access S3"
ROLE_NAME="${EC2_INSTANCE_NAME}-S3AccessRole"
TRUST_POLICY='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ec2.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
if ! aws iam get-role --role-name "$ROLE_NAME" >/dev/null 2>&1; then
  aws iam create-role --role-name "$ROLE_NAME" --assume-role-policy-document "$TRUST_POLICY"
  aws iam attach-role-policy --role-name "$ROLE_NAME" --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess
fi

INSTANCE_PROFILE_NAME="${ROLE_NAME}"
if ! aws iam get-instance-profile --instance-profile-name "$INSTANCE_PROFILE_NAME" >/dev/null 2>&1; then
  aws iam create-instance-profile --instance-profile-name "$INSTANCE_PROFILE_NAME"
  aws iam add-role-to-instance-profile --instance-profile-name "$INSTANCE_PROFILE_NAME" --role-name "$ROLE_NAME"
fi

# Build user-data script to bootstrap
USERDATA=$(cat <<'EOF'
#!/bin/bash
apt-get update -y
apt-get install -y python3-pip git
cd /home/ubuntu
git clone https://github.com/ssamek/ITMO_444_FINAL_PROJECT.git || true
cd Vikas/ITMO_444_544_Fall2025
# install python deps
pip3 install -r api/requirements.txt
# copy frontend into place
mkdir -p /var/www/resume_parser
cp -r frontend/* /var/www/resume_parser/
# create systemd service to run gunicorn
cat > /etc/systemd/system/resume_parser.service <<EOL
[Unit]
Description=Resume Parser Flask App
After=network.target

[Service]
User=ubuntu
WorkingDirectory=/home/ubuntu/ssamek/ITMO_444_FINAL_PROJECT/api
Environment="S3_BUCKET=${S3_BUCKET_NAME}"
ExecStart=/usr/bin/env python3 -m gunicorn -b 0.0.0.0:5000 app:app
Restart=always

[Install]
WantedBy=multi-user.target
EOL

systemctl daemon-reload
systemctl enable resume_parser
systemctl start resume_parser
EOF
)

# Launch EC2 instance
echo "Launching EC2 instance..."
INSTANCE_JSON=$(aws ec2 run-instances \
  --image-id "$AMI_ID" \
  --count 1 \
  --instance-type "$INSTANCE_TYPE" \
  --key-name "$KEY_NAME" \
  --security-group-ids "$SG_ID" \
  --iam-instance-profile Name="$INSTANCE_PROFILE_NAME" \
  --user-data "$USERDATA" \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${EC2_INSTANCE_NAME}}]" \
  --region "$AWS_REGION")

INSTANCE_ID=$(echo "$INSTANCE_JSON" | jq -r '.Instances[0].InstanceId')
echo "Instance launched: $INSTANCE_ID"

# get public IP
echo "Waiting for public IP..."
sleep 8
PUBLIC_IP=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" --query 'Reservations[0].Instances[0].PublicIpAddress' --output text --region "$AWS_REGION")
echo "Public IP: $PUBLIC_IP"

echo "Done. Frontend should be available at http://$PUBLIC_IP:5000 (or via nginx if you configure it)."
