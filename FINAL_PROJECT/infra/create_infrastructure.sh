#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
# load config and utils
if [ ! -f "./config.sh" ]; then
  echo "ERROR: infra/config.sh not found. Create it from the template."
  exit 1
fi
source ./config.sh
source ./cloudwatch_utils.sh

log_to_cw "=== Creating Infrastructure ==="

# Tagging helper
tag_args=(--tag-specifications "ResourceType=vpc,Tags=[{Key=${PROJECT_TAG_KEY},Value=${PROJECT_TAG_VALUE}}]")

# 1) Create S3 bucket (idempotent)
log_to_cw "Creating S3 bucket: $RESUME_BUCKET_NAME"
if aws s3api head-bucket --bucket "$RESUME_BUCKET_NAME" 2>/dev/null; then
  log_to_cw "Bucket already exists: $RESUME_BUCKET_NAME"
else
  if [ "$REGION" = "us-east-1" ]; then
    aws s3api create-bucket --bucket "$RESUME_BUCKET_NAME" --region "$REGION"
  else
    aws s3api create-bucket --bucket "$RESUME_BUCKET_NAME" --region "$REGION" \
      --create-bucket-configuration LocationConstraint="$REGION"
  fi
  log_to_cw "Bucket created: $RESUME_BUCKET_NAME"
fi

# 2) Create VPC (idempotent)
log_to_cw "Creating VPC with CIDR $VPC_CIDR"
VPC_EXISTING=$(aws ec2 describe-vpcs --filters "Name=tag:${PROJECT_TAG_KEY},Values=${PROJECT_TAG_VALUE}" --region "$REGION" --query 'Vpcs[0].VpcId' --output text 2>/dev/null || echo "")
if [ -n "$VPC_EXISTING" ] && [ "$VPC_EXISTING" != "None" ]; then
  VPC_ID="$VPC_EXISTING"
  log_to_cw "Found existing VPC: $VPC_ID"
else
  VPC_ID=$(aws ec2 create-vpc --cidr-block "$VPC_CIDR" --region "$REGION" --query 'Vpc.VpcId' --output text)
  aws ec2 create-tags --resources "$VPC_ID" --tags Key="${PROJECT_TAG_KEY}",Value="${PROJECT_TAG_VALUE}" --region "$REGION"
  aws ec2 modify-vpc-attribute --vpc-id "$VPC_ID" --enable-dns-support "{\"Value\":true}" --region "$REGION" || true
  aws ec2 modify-vpc-attribute --vpc-id "$VPC_ID" --enable-dns-hostnames "{\"Value\":true}" --region "$REGION" || true
  log_to_cw "VPC created: $VPC_ID"
fi
echo "$VPC_ID" > vpc_id.txt

# 3) Create Subnets
create_subnet_if_missing() {
  local cidr=$1; local az=$2
  # check if a subnet with this CIDR in the project exists
  existing=$(aws ec2 describe-subnets --filters "Name=cidr-block,Values=$cidr" "Name=vpc-id,Values=$VPC_ID" --region "$REGION" --query 'Subnets[0].SubnetId' --output text 2>/dev/null || echo "")
  if [ -n "$existing" ] && [ "$existing" != "None" ]; then
    echo "$existing"
  else
    id=$(aws ec2 create-subnet --vpc-id "$VPC_ID" --cidr-block "$cidr" --availability-zone "$az" --region "$REGION" --query 'Subnet.SubnetId' --output text)
    aws ec2 create-tags --resources "$id" --tags Key="${PROJECT_TAG_KEY}",Value="${PROJECT_TAG_VALUE}" --region "$REGION"
    echo "$id"
  fi
}
AZ1="${REGION}a"
AZ2="${REGION}b"
SUBNET1=$(create_subnet_if_missing "$SUBNET_CIDR_1" "$AZ1")
SUBNET2=$(create_subnet_if_missing "$SUBNET_CIDR_2" "$AZ2")
log_to_cw "Subnets in VPC: $SUBNET1, $SUBNET2"

# 4) Internet Gateway
IGW_ID=$(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$VPC_ID" --region "$REGION" --query 'InternetGateways[0].InternetGatewayId' --output text 2>/dev/null || echo "")
if [ -z "$IGW_ID" ] || [ "$IGW_ID" = "None" ]; then
  IGW_ID=$(aws ec2 create-internet-gateway --region "$REGION" --query 'InternetGateway.InternetGatewayId' --output text)
  aws ec2 attach-internet-gateway --internet-gateway-id "$IGW_ID" --vpc-id "$VPC_ID" --region "$REGION"
  aws ec2 create-tags --resources "$IGW_ID" --tags Key="${PROJECT_TAG_KEY}",Value="${PROJECT_TAG_VALUE}" --region "$REGION"
  log_to_cw "Created & attached IGW: $IGW_ID"
else
  log_to_cw "Found existing IGW: $IGW_ID"
fi

# 5) Route Table + Route to IGW
RTB_ID=$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$VPC_ID" --region "$REGION" --query 'RouteTables[0].RouteTableId' --output text)
if [ -z "$RTB_ID" ] || [ "$RTB_ID" = "None" ]; then
  RTB_ID=$(aws ec2 create-route-table --vpc-id "$VPC_ID" --region "$REGION" --query 'RouteTable.RouteTableId' --output text)
  aws ec2 create-tags --resources "$RTB_ID" --tags Key="${PROJECT_TAG_KEY}",Value="${PROJECT_TAG_VALUE}" --region "$REGION"
  log_to_cw "Created route table: $RTB_ID"
fi
# create route (ignore error if exists)
aws ec2 create-route --route-table-id "$RTB_ID" --destination-cidr-block 0.0.0.0/0 --gateway-id "$IGW_ID" --region "$REGION" 2>/dev/null || true
# associate subnets
aws ec2 associate-route-table --route-table-id "$RTB_ID" --subnet-id "$SUBNET1" --region "$REGION" 2>/dev/null || true
aws ec2 associate-route-table --route-table-id "$RTB_ID" --subnet-id "$SUBNET2" --region "$REGION" 2>/dev/null || true
log_to_cw "Route table associated with subnets"

# 6) Security Group
# Allow SSH only from your IP and HTTP from anywhere (change as needed)
MY_IP=$(curl -s ifconfig.me || echo "0.0.0.0")
MY_CIDR="${MY_IP}/32"
SG_EXISTING=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=$SECURITY_GROUP_NAME" "Name=vpc-id,Values=$VPC_ID" --region "$REGION" --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null || echo "")
if [ -n "$SG_EXISTING" ] && [ "$SG_EXISTING" != "None" ]; then
  SG_ID="$SG_EXISTING"
  log_to_cw "Found existing SG: $SG_ID"
else
  SG_ID=$(aws ec2 create-security-group --group-name "$SECURITY_GROUP_NAME" --description "$SECURITY_GROUP_DESC" --vpc-id "$VPC_ID" --region "$REGION" --query 'GroupId' --output text)
  aws ec2 create-tags --resources "$SG_ID" --tags Key="${PROJECT_TAG_KEY}",Value="${PROJECT_TAG_VALUE}" --region "$REGION"
  log_to_cw "Created SG: $SG_ID"
fi
# try to authorize (ignore failure if rule exists)
aws ec2 authorize-security-group-ingress --group-id "$SG_ID" --protocol tcp --port 22 --cidr "$MY_CIDR" --region "$REGION" 2>/dev/null || true
aws ec2 authorize-security-group-ingress --group-id "$SG_ID" --protocol tcp --port 80 --cidr "0.0.0.0/0" --region "$REGION" 2>/dev/null || true
aws ec2 authorize-security-group-ingress --group-id "$SG_ID" --protocol tcp --port 5000 --cidr "0.0.0.0/0" --region "$REGION" 2>/dev/null || true

# save SG
echo "$SG_ID" > sg_id.txt

# 7) Key pair (create locally if not exists)
if [ ! -f "$KEY_FILE" ] && [ "${CREATE_KEYPAIR:-false}" = true ]; then
  log_to_cw "Creating key pair $KEY_NAME and saving to $KEY_FILE"
  aws ec2 create-key-pair --key-name "$KEY_NAME" --key-type "$KEY_TYPE" --region "$REGION" --query 'KeyMaterial' --output text > "$KEY_FILE"
  chmod 400 "$KEY_FILE"
else
  log_to_cw "Key file exists or CREATE_KEYPAIR disabled"
fi

# 8) Launch EC2 instance (idempotent: launches a new one and appends to instance_id.txt)
log_to_cw "Preparing user-data and launching EC2 instance"

read -r -d '' USER_DATA <<'EOF' || true
#!/bin/bash
set -e
# Basic bootstrap for Ubuntu 22.04/20.04
apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get install -y python3-pip git nginx
# Create app directory
APP_DIR=/home/ubuntu/resume-app
mkdir -p $APP_DIR
chown -R ubuntu:ubuntu $APP_DIR

# Clone repo (placeholder - change to your repo)
if [ ! -d /home/ubuntu/resume-app-source ]; then
  sudo -u ubuntu git clone https://github.com/your-username/Vikas.git /home/ubuntu/resume-app-source || true
else
  cd /home/ubuntu/resume-app-source && sudo -u ubuntu git pull || true
fi

# Move API folder into place (adjust paths if your repo differs)
cp -r /home/ubuntu/resume-app-source/api $APP_DIR/
cp -r /home/ubuntu/resume-app-source/frontend $APP_DIR/

cd $APP_DIR/api || exit 0
pip3 install --upgrade pip
pip3 install -r requirements.txt || true

# set env for S3 bucket
echo "export RESUME_BUCKET_NAME=${RESUME_BUCKET_NAME}" > /etc/profile.d/resume_app.sh

# start gunicorn under ubuntu user
sudo -u ubuntu nohup gunicorn -w 2 -b 0.0.0.0:5000 app:app --chdir $APP_DIR/api > /var/log/resume_app_gunicorn.log 2>&1 &
EOF

INSTANCE_ID=$(aws ec2 run-instances \
  --image-id "$AMI_ID" \
  --instance-type "$INSTANCE_TYPE" \
  --key-name "$KEY_NAME" \
  --security-group-ids "$SG_ID" \
  --subnet-id "$SUBNET1" \
  --associate-public-ip-address \
  --user-data "$USER_DATA" \
  --region "$REGION" \
  --tag-specifications "ResourceType=instance,Tags=[{Key=${PROJECT_TAG_KEY},Value=${PROJECT_TAG_VALUE}}]" \
  --query "Instances[0].InstanceId" --output text)

if [ -z "$INSTANCE_ID" ] || [ "$INSTANCE_ID" = "None" ]; then
  echo "ERROR: Failed to launch instance"
  exit 1
fi

aws ec2 wait instance-running --instance-ids "$INSTANCE_ID" --region "$REGION"
PUBLIC_IP=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" --region "$REGION" --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
echo "$INSTANCE_ID" >> instance_id.txt
echo "$PUBLIC_IP" >> instance_ip.txt

log_to_cw "EC2 instance launched: $INSTANCE_ID ($PUBLIC_IP)"
send_cw_metric 1

echo "=== create_infrastructure.sh completed ==="
