#!/usr/bin/env bash
set -euo pipefail
CONFIG_FILE="$(dirname "$0")/config.txt"
source "$CONFIG_FILE"

# Very basic EC2 launch for demo purposes. Using user-data to clone the repository and run the app.
USER_DATA_FILE="$(mktemp)"
cat > "$USER_DATA_FILE" <<'EOF'
#!/bin/bash
yum update -y
yum install -y python3 git
pip3 install --upgrade pip
git clone https://github.com/vsanil1/Vikas.git /home/ec2-user/resume-app || (cd /home/ec2-user/resume-app && git pull)
cd /home/ec2-user/resume-app/api
pip3 install -r requirements.txt
# export S3 bucket env var
echo "export S3_BUCKET=${S3_BUCKET_NAME}" >> /etc/profile.d/resume_app.sh
# Run with gunicorn in background (basic)
gunicorn -w 2 -b 0.0.0.0:5000 app:app --chdir /home/ec2-user/resume-app/api --daemon
EOF

# Launch EC2
echo "Launching EC2 instance..."
INSTANCE_ID=$(aws ec2 run-instances \
  --image-id "${AMI_ID}" \
  --instance-type "${INSTANCE_TYPE}" \
  --key-name "${KEY_NAME}" \
  --security-groups "resume-uploader-sg" \
  --user-data file://${USER_DATA_FILE} \
  --query "Instances[0].InstanceId" --output text)

echo "Instance launched: $INSTANCE_ID"
echo "Waiting for public IP..."
aws ec2 wait instance-running --instance-ids "$INSTANCE_ID"
PUB_IP=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" --query "Reservations[0].Instances[0].PublicIpAddress" --output text)
echo "Instance public IP: $PUB_IP (app should serve on port 5000)"
rm -f "$USER_DATA_FILE"
