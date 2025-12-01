# api/app.py
import os
import uuid
import boto3
from flask import Flask, request, jsonify, send_from_directory
from werkzeug.utils import secure_filename
from utils import parse_docx, parse_pdf

# Config from env or defaults
S3_BUCKET = os.environ.get("S3_BUCKET", "resume-parser-bucket")
UPLOAD_FOLDER = "/tmp/resumes"
ALLOWED_EXTENSIONS = {"pdf", "docx"}

os.makedirs(UPLOAD_FOLDER, exist_ok=True)

app = Flask(__name__)
app.config["UPLOAD_FOLDER"] = UPLOAD_FOLDER

s3 = boto3.client("s3")

def allowed_file(filename):
    return "." in filename and filename.rsplit(".", 1)[1].lower() in ALLOWED_EXTENSIONS

@app.route("/health", methods=["GET"])
def health():
    return jsonify({"status": "ok"}), 200

@app.route("/upload", methods=["POST"])
def upload_resume():
    if "file" not in request.files:
        return jsonify({"error": "no file part"}), 400
    f = request.files["file"]
    if f.filename == "":
        return jsonify({"error": "no selected file"}), 400
    if not allowed_file(f.filename):
        return jsonify({"error": "file type not allowed"}), 400

    filename = secure_filename(f.filename)
    uid = str(uuid.uuid4())
    local_path = os.path.join(app.config["UPLOAD_FOLDER"], f"{uid}_{filename}")
    f.save(local_path)

    ext = filename.rsplit(".", 1)[1].lower()
    extracted = {}
    try:
        if ext == "docx":
            extracted = parse_docx(local_path)
        elif ext == "pdf":
            extracted = parse_pdf(local_path)
    except Exception as e:
        return jsonify({"error": f"parsing failed: {str(e)}"}), 500

    # Save raw file to S3
    s3_key_file = f"uploads/{uid}/{filename}"
    s3.upload_file(local_path, S3_BUCKET, s3_key_file)

    # Save parsed JSON to S3
    s3_key_json = f"records/{uid}/parsed.json"
    s3.put_object(Body=str(extracted).encode("utf-8"), Bucket=S3_BUCKET, Key=s3_key_json)

    return jsonify({"id": uid, "s3_file": s3_key_file, "parsed_s3": s3_key_json, "parsed": extracted}), 201

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
