from docx import Document
import PyPDF2
import os


def extract_text_from_pdf(file_path):
    """Safely extract text from a PDF."""
    text_parts = []
    with open(file_path, "rb") as f:
        reader = PyPDF2.PdfReader(f)

        for page in reader.pages:
            try:
                page_text = page.extract_text()
                if page_text:
                    text_parts.append(page_text)
            except Exception:
                continue  # Skip unreadable pages

    return "\n".join(text_parts)


def extract_text_from_docx(file_path):
    """Safely extract text from a DOCX file."""
    doc = Document(file_path)
    return "\n".join(p.text for p in doc.paragraphs)


def parse_resume(file_path):
    """Very simple structured resume parser."""
    data = {
        "personal": {},
        "education": [],
        "experience": [],
        "raw_text": ""
    }

    # Extract text
    if file_path.lower().endswith(".pdf"):
        text = extract_text_from_pdf(file_path)
    elif file_path.lower().endswith(".docx"):
        text = extract_text_from_docx(file_path)
    else:
        raise ValueError("Unsupported file type. Only PDF and DOCX are supported.")

    data["raw_text"] = text  # Store raw extracted text

    # Tokenize for simple parser
    lines = [line.strip() for line in text.splitlines() if line.strip()]

    section = None
    for line in lines:
        # Section detection
        if line.lower().startswith("education"):
            section = "education"
            continue
        if line.lower().startswith("experience"):
            section = "experience"
            continue
        if "contact" in line.lower() or "personal" in line.lower():
            section = "personal"
            continue

        # Add parsed lines
        if section == "personal":
            if ":" in line:
                key, value = line.split(":", 1)
                data["personal"][key.strip()] = value.strip()

        elif section in ("education", "experience"):
            data[section].append(line)

    return data
