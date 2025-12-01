from docx import Document
import PyPDF2

def parse_resume(file_path):
    data = {"personal": {}, "education": [], "experience": []}
    if file_path.endswith(".pdf"):
        with open(file_path, 'rb') as f:
            reader = PyPDF2.PdfReader(f)
            text = " ".join(page.extract_text() for page in reader.pages)
    else:
        doc = Document(file_path)
        text = "\n".join([p.text for p in doc.paragraphs])

    # Dummy parser: assumes Harvard template with sections
    lines = text.splitlines()
    section = None
    for line in lines:
        line = line.strip()
        if "Education" in line:
            section = "education"
            continue
        if "Experience" in line:
            section = "experience"
            continue
        if "Personal" in line or "Contact" in line:
            section = "personal"
            continue
        if section:
            if section == "personal":
                key_val = line.split(":", 1)
                if len(key_val) == 2:
                    data["personal"][key_val[0].strip()] = key_val[1].strip()
            else:
                if line:
                    data[section].append(line)
    return data

