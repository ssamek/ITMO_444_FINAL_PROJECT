# Resume Parser Flask App with AWS Deployment
## Project Overview
This project is a web application to upload resumes (Word or PDF) following the Harvard resume template. The app extracts:
•	Personal details
•	Education
•	Work experience
and stores them as records in AWS S3.
The project includes:
1.	Flask API backend for file uploads and parsing.
2.	Simple frontend for user interaction.
3.	AWS CLI-based infrastructure provisioning (EC2, VPC, S3, Security Groups).
4.	CloudWatch logging and monitoring.
5.	Auto-scaling support with multiple EC2 instances.
6.	Automated teardown to avoid extra costs.
________________________________________
Resume Template (Harvard Style)
To ensure correct parsing, resumes should follow this template:
------------------------------------------------------
PERSONAL INFORMATION
------------------------------------------------------
Name: John Doe
Email: john.doe@example.com
Phone: +1 123-456-7890
LinkedIn: linkedin.com/in/johndoe
GitHub: github.com/johndoe
Address: 123 Main Street, City, Country

------------------------------------------------------
EDUCATION
------------------------------------------------------
University Name, Degree, Major
City, Country
Start Date – End Date
GPA: 3.8/4.0
Relevant Courses: Course1, Course2, Course3

------------------------------------------------------
WORK EXPERIENCE
------------------------------------------------------
Company Name, Job Title
City, Country
Start Date – End Date
- Responsibility or achievement 1
- Responsibility or achievement 2

Company Name, Job Title
City, Country
Start Date – End Date
- Responsibility or achievement 1
- Responsibility or achievement 2

------------------------------------------------------
SKILLS
------------------------------------------------------
- Programming Languages: Python, Java, C++
- Tools: Git, Docker, AWS
- Languages: English (Fluent), Spanish (Intermediate)

------------------------------------------------------
PROJECTS (Optional)
------------------------------------------------------
Project Name
Description: Short description of the project.
Technologies Used: Python, Flask, AWS

## Note: The parser assumes these sections exist and extracts details accordingly.
________________________________________
Repository Structure   
│   
├─ api/   
│   ├── app.py               # Flask API code   
│   ├── requirements.txt     # Python dependencies   
│   └── utils.py             # Resume parsing utilities   
│   
├── frontend/   
│   ├── index.html           # Simple file upload page   
|   ├── style.css            # Simple style file   
│   └── script.js            # Frontend JS logic   
│   
├── infra/   
│   ├── config.txt           # AWS configuration   
│   ├── cloudwatch_utils.sh  # CloudWatch logging helper   
│   ├── create_infrastructure.sh   
│   ├── scale_infrastructure.sh   
│   ├── setup_monitoring.sh   
│   ├── schedule_teardown.sh   
│   └── destroy_infrastructure.sh   
│   
└── README.md   
________________________________________
Features
•	Upload Word or PDF resumes via the web interface.   
•	Automatically extract key details using Python docx and PDF libraries.   
•	Store resume data in S3 buckets.   
•	Frontend built with simple HTML/JS served via Flask.   
•	AWS infrastructure provisioned via CLI scripts:   
  o	EC2 instances (backend + frontend)   
  o	VPC, subnets, security groups   
  o	S3 bucket for resume storage   
  o	CloudWatch logs and metrics   
•	Scaling support (additional EC2 instances can be launched).   
•	Automated teardown via cron to avoid unnecessary costs.   
________________________________________
Setup Instructions   
1. Download the repository   
Go to git repository https://github.com/vsanil1/Vikas.git   
Click Code-->Local-->Dowload Zip   
Extract file and work on ITMO_444_544_Fall2025/FINAL_PROJECT.   
________________________________________
2. Configure AWS   
Edit infra/config.txt with your AWS details. Replace ALARM_EMAIL with your email for CloudWatch alarm notifications.
________________________________________
3. Create Infrastructure   
cd infra   
bash create_infrastructure.sh   
•	Creates VPC, subnets, security groups, EC2 instance, and S3 bucket.
________________________________________
4. Deploy Application  
bash deploy_infrastructure.sh   
•	The EC2 instance will automatically clone the GitHub repo.   
•	Python dependencies are installed.   
•	Flask API and frontend will start via Gunicorn.   
Access the frontend via http://<EC2_PUBLIC_IP>.   
________________________________________
5. Scaling Infrastructure   
bash scale_infrastructure.sh
•	Adds new EC2 instances running the Flask API automatically.
________________________________________
6. Setup Monitoring   
bash setup_monitoring.sh   
•	Creates CloudWatch logs, metrics, and alarms.   
________________________________________
7. Schedule Automatic Teardown   
bash schedule_teardown.sh   
•	Infrastructure will be automatically destroyed after AUTO_TEARDOWN_HOURS.   
________________________________________
8. Manual Teardown (Optional)   
bash destroy_infrastructure.sh   
•	Terminates all EC2 instances, deletes S3 bucket, security groups, VPC.   
•	Removes CloudWatch logs and alarms.   
________________________________________
Frontend Usage   
1.	Open the EC2 public IP in a browser.   
2.	Choose a resume file (PDF or DOCX).   
3.	Click Upload.   
4.	Confirmation will appear once uploaded.   
5.	Data is automatically saved to the S3 bucket.   
________________________________________
Backend API Endpoints   
Endpoint	Method	Description   
/upload	POST	Upload resume file   
/health	GET	Check API health status   
________________________________________
AWS Services Used (Free-tier compatible)   
•	EC2 (t3.micro)   
•	S3   
•	CloudWatch (logs + metrics)   
•	SNS (email alerts)   
•	Security Groups   
•	VPC with public subnets   
________________________________________
Notes   
•	Make sure AWS CLI is installed and configured with credentials.   
•	All infrastructure scripts are idempotent; can run multiple times safely.   
•	All project code is intended for educational and testing purposes in the AWS free-tier.   
