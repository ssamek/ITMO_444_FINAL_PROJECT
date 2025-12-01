import os
import json
import boto3
from botocore.exceptions import ClientError
from flask import Flask, request, jsonify, send_from_directory
from werkzeug.utils import secure_filename
from resume_parser import parse_resume

app = Flask(__name__, static_folder='../frontend', static_url_path='/')

# Load bucket name
S3_BUCKET = os.environ.get("RESUME_BUCKET_NAME")
if not S3_BUCKET:
    raise RuntimeError("Environment variable RESUME_BUCKET_NAME is not set.")

# Initialize S3 client
s3_client = boto3.client("s3")


@app.route('/upload', methods=['POST'])
def upload_resume():
    """Handles resume uploads, parsing, and S3 storage."""
    if 'file' not in request.files:
        return jsonify({'status': 'error', 'message': 'No file provided'}), 400

    file = request.files['file']

    if file.filename == "":
        return jsonify({'status': 'error', 'message': 'No filename provided'}), 400

    filename = secure_filename(file.filename)
    file_path = f"/tmp/{filename}"
    file.save(file_path)

    try:
        parsed_data = parse_resume(file_path)
    except Exception as e:
        return jsonify({
            "status": "error",
            "message": f"Failed to parse resume: {str(e)}"
        }), 500

    # Upload parsed JSON to S3
    s3_key = f"resumes/{os.path.splitext(filename)[0]}.json"

    try:
        s3_client.put_object(
            Bucket=S3_BUCKET,
            Key=s3_key,
            Body=json.dumps(parsed_data, indent=2),
            ContentType="application/json"
        )
    except ClientError as e:
        return jsonify({
            "status": "error",
            "message": f"Failed to upload to S3: {str(e)}"
        }), 500

    return jsonify({
        "status": "success",
        "s3_key": s3_key,
        "parsed_data": parsed_data
    })


# Serve frontend SPA
@app.route('/')
def index():
    return send_from_directory(app.static_folder, "index.html")


if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
