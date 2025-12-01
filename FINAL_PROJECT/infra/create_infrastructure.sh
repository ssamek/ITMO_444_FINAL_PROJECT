#!/bin/bash
set -e
source config.txt
source cloudwatch_utils.sh

log_to_cw "=== Creating Infrastructure ==="
echo "=== Starting infrastructure creation ==="

# ----------------------------
# Create S3 Bucket
# ----------------------------
if [ -z "$RESUME_BUCKET_NAME" ]; then
    RESUME_BUCKET_NAME="resume-parser-$(whoami)-$(date +%s)"
fi
echo "Using S3 bucket name: $RESUME_BUCKET_NAME"

aws s3api create-bucket --bucket "$RESUME_BUCKET_NAME" --region "$REGION" \
    --create-bucket-configuration LocationConstraint="$REGION" 2>/dev/null || true
log_to_cw "S3 bucket ready: $RESUME_BUCKET_NAME"

# ----------------------------
# VPC
# ----------------------------
VPC_ID=$(aws ec2 create-vpc --cidr-block "$VPC_CIDR" --region "$REGION" \
    --query "Vpc.VpcId" --output text)
echo "$VPC_ID" > vpc_id.txt
log_to_cw "VPC created: $VPC_ID"

# ----------------------------
# Subnets
# ----------------------------
SUBNET1=$(aws ec2 create-subnet --vpc-id "$VPC_ID" --cidr-block "$SUBNET_CIDR_1" \
    --availability-zone "${REGION}a" --query "Subnet.SubnetId" --output text)
SUBNET2=$(aws ec2 create-subnet --vpc-id "$VPC_ID" --cidr-block "$SUBNET_CIDR_2" \
    --availability-zone "${REGION}b" --query "Subnet.SubnetId" --output text)
log_to_cw "Subnets created: $SUBNET1, $SUBNET2"

# ----------------------------
# Internet Gateway & Route Table
# ----------------------------
IGW_ID=$(aws ec2 create-internet-gateway --region "$REGION" \
    --query "InternetGateway.InternetGatewayId" --output text)
aws ec2 attach-internet-gateway --vpc-id "$VPC_ID" --internet-gateway-id "$IGW_ID" --region "$REGION"
log_to_cw "Internet Gateway attached: $IGW_ID"

RTB_ID=$(aws ec2 create-route-table --vpc-id "$VPC_ID" --region "$REGION" \
    --query "RouteTable.RouteTableId" --output text)
aws ec2 create-route --route-table-id "$RTB_ID" --destination-cidr-block 0.0.0.0/0 \
    --gateway-id "$IGW_ID" --region "$REGION"
aws ec2 associate-route-table --route-table-id "$RTB_ID" --subnet-id "$SUBNET1" --region "$REGION"
aws ec2 associate-route-table --route-table-id "$RTB_ID" --subnet-id "$SUBNET2" --region "$REGION"

# ----------------------------
# Security Group
# ----------------------------
MY_IP=$(curl -s ifconfig.me)/32
SG_ID=$(aws ec2 create-security-group --group-name "$SECURITY_GROUP_NAME" \
    --description "$SECURITY_GROUP_DESC" --vpc-id "$VPC_ID" --region "$REGION" \
    --query "GroupId" --output text)
if [ -z "$SG_ID" ] || [ "$SG_ID" == "None" ]; then
    echo "ERROR: Security Group creation failed"
    exit 1
fi
echo "Security Group created: $SG_ID"

aws ec2 authorize-security-group-ingress --group-id "$SG_ID" --protocol tcp --port 22 --cidr "$MY_IP" --region "$REGION"
aws ec2 authorize-security-group-ingress --group-id "$SG_ID" --protocol tcp --port 80 --cidr 0.0.0.0/0 --region "$REGION"

# ----------------------------
# Key Pair
# ----------------------------
KEY_FILE="/home/vagrant/${KEY_NAME}.pem"
rm -f "$KEY_FILE"

aws ec2 create-key-pair --key-name "$KEY_NAME" --key-type "$KEY_TYPE" --region "$REGION" \
    --query "KeyMaterial" --output text > "$KEY_FILE"
chmod 400 "$KEY_FILE"
echo "Key pair saved to $KEY_FILE"

# ----------------------------
# AMI
# ----------------------------
echo "Searching for Ubuntu AMI..."
AMI_ID="ami-03deb8c961063af8c"
echo "Using AMI_ID: $AMI_ID"

if [ -z "$AMI_ID" ] || [ "$AMI_ID" == "None" ]; then
    echo "ERROR: No valid AMI found. Please check UBUNTU_FILTER, UBUNTU_OWNER, and REGION."
    exit 1
fi
echo "Using AMI_ID: $AMI_ID"

# ----------------------------
# UserData for EC2
# ----------------------------
USER_DATA=$(cat <<'EOF'
#!/bin/bash
# Update and install packages
sudo apt update -y
sudo apt install -y python3-pip git nginx

# Export S3 bucket name (used by Flask)
export RESUME_BUCKET_NAME=YOUR_BUCKET_NAME

# Go to home folder
cd /home/ubuntu

# Clone repo
git clone https://github.com/ssamek/ITMO_444_FINAL_PROJECT.git resume-flask-api

# Install Python dependencies
cd /home/ubuntu/resume-flask-api
pip3 install -r requirements.txt

# Set up Nginx to proxy requests to Gunicorn
sudo tee /etc/nginx/sites-available/resume-app > /dev/null <<'NGINXCONF'
server {
    listen 80;
    server_name _;

    location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
NGINXCONF

# Enable Nginx site
sudo ln -s /etc/nginx/sites-available/resume-app /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl restart nginx

# Create systemd service for Flask app
sudo tee /etc/systemd/system/resume-app.service > /dev/null <<'SERVICECONF'
[Unit]
Description=Gunicorn Resume App
After=network.target

[Service]
User=ubuntu
WorkingDirectory=/home/ubuntu/resume-flask-api
ExecStart=/usr/local/bin/gunicorn -b 0.0.0.0:5000 app:app

[Install]
WantedBy=multi-user.target
SERVICECONF

# Reload systemd, enable and start service
sudo systemctl daemon-reload
sudo systemctl enable resume-app
sudo systemctl start resume-app

EOF
)

# ----------------------------
# Launch EC2
# ----------------------------
echo "Launching EC2 instance..."
INSTANCE_ID=$(aws ec2 run-instances --image-id "$AMI_ID" --count 1 \
    --instance-type "$INSTANCE_TYPE" --key-name "$KEY_NAME" \
    --security-group-ids "$SG_ID" --subnet-id "$SUBNET1" \
    --associate-public-ip-address \
    --user-data "$USER_DATA" \
    --region "$REGION" \
    --query "Instances[0].InstanceId" --output text)

if [ -z "$INSTANCE_ID" ] || [ "$INSTANCE_ID" == "None" ]; then
    echo "ERROR: EC2 instance launch failed"
    exit 1
fi

aws ec2 wait instance-running --instance-ids "$INSTANCE_ID" --region "$REGION"
PUBLIC_IP=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" \
    --query "Reservations[0].Instances[0].PublicIpAddress" --output text --region "$REGION")

echo "$INSTANCE_ID" > instance_id.txt
echo "$PUBLIC_IP" > instance_ip.txt
log_to_cw "EC2 instance created: $INSTANCE_ID ($PUBLIC_IP)"
send_cw_metric 1

echo "=== Infrastructure creation completed successfully ==="
