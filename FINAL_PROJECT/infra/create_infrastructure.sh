#!/bin/bash
set -e
source config.txt
source cloudwatch_utils.sh

log_to_cw "=== Creating Infrastructure ==="

# Create S3 bucket
aws s3api create-bucket --bucket $RESUME_BUCKET_NAME --region $REGION \
    --create-bucket-configuration LocationConstraint=$REGION 2>/dev/null || true
log_to_cw "S3 bucket created: $RESUME_BUCKET_NAME"

# VPC
VPC_ID=$(aws ec2 create-vpc --cidr-block "$VPC_CIDR" --region "$REGION" \
    --query "Vpc.VpcId" --output text)
echo "$VPC_ID" > vpc_id.txt
log_to_cw "VPC created: $VPC_ID"

# Subnets
SUBNET1=$(aws ec2 create-subnet --vpc-id "$VPC_ID" --cidr-block "$SUBNET_CIDR_1" \
    --availability-zone "${REGION}a" --query "Subnet.SubnetId" --output text)
SUBNET2=$(aws ec2 create-subnet --vpc-id "$VPC_ID" --cidr-block "$SUBNET_CIDR_2" \
    --availability-zone "${REGION}b" --query "Subnet.SubnetId" --output text)
log_to_cw "Subnets created: $SUBNET1, $SUBNET2"

# Internet Gateway
IGW_ID=$(aws ec2 create-internet-gateway --region "$REGION" \
    --query "InternetGateway.InternetGatewayId" --output text)
aws ec2 attach-internet-gateway --vpc-id "$VPC_ID" --internet-gateway-id "$IGW_ID" --region "$REGION"
log_to_cw "Internet Gateway attached: $IGW_ID"

# Route Table
RTB_ID=$(aws ec2 create-route-table --vpc-id "$VPC_ID" --region "$REGION" \
    --query "RouteTable.RouteTableId" --output text)
aws ec2 create-route --route-table-id "$RTB_ID" --destination-cidr-block 0.0.0.0/0 \
    --gateway-id "$IGW_ID" --region "$REGION"
aws ec2 associate-route-table --route-table-id "$RTB_ID" --subnet-id "$SUBNET1" --region "$REGION"
aws ec2 associate-route-table --route-table-id "$RTB_ID" --subnet-id "$SUBNET2" --region "$REGION"

# Security Group
MY_IP=$(curl -s ifconfig.me)/32
SG_ID=$(aws ec2 create-security-group --group-name "$SECURITY_GROUP_NAME" \
    --description "$SECURITY_GROUP_DESC" --vpc-id "$VPC_ID" --region "$REGION" \
    --query "GroupId" --output text)
aws ec2 authorize-security-group-ingress --group-id "$SG_ID" --protocol tcp --port 22 --cidr "$MY_IP" --region "$REGION"
aws ec2 authorize-security-group-ingress --group-id "$SG_ID" --protocol tcp --port 80 --cidr 0.0.0.0/0 --region "$REGION"

# Key Pair
EXISTING_KEY=$(aws ec2 describe-key-pairs \
    --key-names "$KEY_NAME" \
    --region "$REGION" \
    --query "KeyPairs[0].KeyName" \
    --output text 2>/dev/null || true)

if [[ "$EXISTING_KEY" == "$KEY_NAME" ]]; then
    echo "Key pair already exists, skipping creation."
else
    aws ec2 create-key-pair --key-name "$KEY_NAME" --key-type "$KEY_TYPE" --region "$REGION" \
        --query "KeyMaterial" --output text > "$KEY_FILE"
    chmod 400 "$KEY_FILE"
fi

# AMI
AMI_ID=$(aws ec2 describe-images --owners "$UBUNTU_OWNER" \
    --filters "Name=name,Values=$UBUNTU_FILTER" \
    --region "$REGION" --query "Images|sort_by(@,&CreationDate)|[-1].ImageId" --output text)

# Launch EC2 via UserData
USER_DATA=$(cat <<'EOF'
#!/bin/bash
sudo apt update -y
sudo apt install -y python3-pip git nginx

export RESUME_BUCKET_NAME=${RESUME_BUCKET_NAME}

git clone https://github.com/ssamek/ITMO_444_FINAL_PROJECT.git /home/ubuntu/resume-flask-api
git clone https://github.com/ssamek/ITMO_444_FINAL_PROJECT.git /home/ubuntu/resume-flask-frontend

cd /home/ubuntu/resume-flask-api
pip3 install -r requirements.txt

rm -rf /home/ubuntu/resume-flask-api/frontend
cp -r /home/ubuntu/resume-flask-frontend /home/ubuntu/resume-flask-api/frontend

nohup gunicorn -b 0.0.0.0:5000 app:app &
EOF
)


INSTANCE_ID=$(aws ec2 run-instances --image-id "$AMI_ID" --count 1 \
    --instance-type "$INSTANCE_TYPE" --key-name "$KEY_NAME" \
    --security-group-ids "$SG_ID" --subnet-id "$SUBNET1" \
    --associate-public-ip-address \
    --user-data "$USER_DATA" \
    --region "$REGION" \
    --query "Instances[0].InstanceId" --output text)

aws ec2 wait instance-running --instance-ids "$INSTANCE_ID" --region "$REGION"
PUBLIC_IP=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" \
    --query "Reservations[0].Instances[0].PublicIpAddress" --output text --region "$REGION")

echo "$INSTANCE_ID" > instance_id.txt
echo "$PUBLIC_IP" > instance_ip.txt
log_to_cw "EC2 instance created: $INSTANCE_ID ($PUBLIC_IP)"
send_cw_metric 1