#!/bin/bash
set -e
source config.txt
source cloudwatch_utils.sh

log_to_cw "Scaling infrastructure: launching additional EC2 instance..."

VPC_ID=$(cat vpc_id.txt)
SUBNET1=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" \
  --query "Subnets[0].SubnetId" --output text --region "$REGION")
SG_ID=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=$SECURITY_GROUP_NAME" \
  --query "SecurityGroups[0].GroupId" --output text --region "$REGION")
AMI_ID=$(aws ec2 describe-images --owners "$UBUNTU_OWNER" \
    --filters "Name=name,Values=$UBUNTU_FILTER" \
    --region "$REGION" --query "Images|sort_by(@,&CreationDate)|[-1].ImageId" --output text)

USER_DATA="#!/bin/bash
sudo apt update -y
sudo apt install -y python3-pip git nginx
export RESUME_BUCKET_NAME=$RESUME_BUCKET_NAME
git clone https://github.com/your-username/resume-flask-api.git /home/ubuntu/resume-flask-api
git clone https://github.com/your-username/resume-flask-frontend.git /home/ubuntu/resume-flask-frontend
cd /home/ubuntu/resume-flask-api
pip3 install -r requirements.txt
rm -rf /home/ubuntu/resume-flask-api/frontend
cp -r /home/ubuntu/resume-flask-frontend /home/ubuntu/resume-flask-api/frontend
nohup gunicorn -b 0.0.0.0:5000 app:app &"

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

echo "$INSTANCE_ID" >> instance_id.txt
echo "$PUBLIC_IP" >> instance_ip.txt

log_to_cw "Additional EC2 instance launched: $INSTANCE_ID ($PUBLIC_IP)"
send_cw_metric 1

