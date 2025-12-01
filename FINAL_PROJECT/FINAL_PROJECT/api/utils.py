# api/utils.py
import re
from docx import Document
import pdfplumber

SECTION_HEADERS = ["PERSONAL INFORMATION", "EDUCATION", "WORK EXPERIENCE", "SKILLS", "PROJECTS"]

def text_to_sections(text):
    # Normalize
    lines = [l.strip() for l in text.splitlines() if l.strip() != ""]
    sections = {}
    current = None
    for line in lines:
        up = line.upper()
        if any(up.startswith(h) for h in SECTION_HEADERS):
            current = up.split()[0] if up else None
            sections[up] = []
            continue
        if current is not None:
            sections.setdefault(current, []).append(line)
    return sections

def parse_personal(lines):
    text = " ".join(lines)
    res = {}
    # Name:
    m = re.search(r"Name:\s*(.+?)(?:Email:|Phone:|$)", text, re.I)
    if m:
        res["name"] = m.group(1).strip()
    m = re.search(r"Email:\s*([^\s]+)", text, re.I)
    if m:
        res["email"] = m.group(1).strip()
    m = re.search(r"Phone:\s*([+\d\-\s\(\)]+)", text, re.I)
    if m:
        res["phone"] = m.group(1).strip()
    m = re.search(r"LinkedIn:\s*([^\s]+)", text, re.I)
    if m:
        res["linkedin"] = m.group(1).strip()
    m = re.search(r"GitHub:\s*([^\s]+)", text, re.I)
    if m:
        res["github"] = m.group(1).strip()
    return res

def parse_education(lines):
    # Basic parsing into list of dicts assuming Harvard resume style
    entries = []
    current = {}
    for line in lines:
        if "," in line and "University" in line or "College" in line:
            if current:
                entries.append(current)
                current = {}
            current["institution"] = line
        elif "GPA" in line or "GPA:" in line:
            current.setdefault("details", []).append(line)
        else:
            current.setdefault("details", []).append(line)
    if current:
        entries.append(current)
    return entries

def parse_work_experience(lines):
    entries = []
    current = {}
    for line in lines:
        # detect header-like lines: "Company Name, Job Title City, Country Start Date – End Date"
        if re.search(r"\d{4}", line) and "," in line:
            if current:
                entries.append(current)
            current = {"header": line, "bullets": []}
        else:
            current.setdefault("bullets", []).append(line)
    if current:
        entries.append(current)
    return entries

def parse_docx(path):
    doc = Document(path)
    text = "\n".join([p.text for p in doc.paragraphs])
    return parse_text(text)

def parse_pdf(path):
    text_pages = []
    with pdfplumber.open(path) as pdf:
        for p in pdf.pages:
            text_pages.append(p.extract_text() or "")
    text = "\n".join(text_pages)
    return parse_text(text)

def parse_text(text):
    # naive section splitting by header lines from template
    sections = {}
    # Find indices of headers
    for header in SECTION_HEADERS:
        pattern = re.compile(rf"{header}", re.I)
        m = pattern.search(text)
        if m:
            # grab the text from header to next header
            sections[header.upper()] = []
    # Fallback: split by headers by simple splitting
    pieces = re.split(r"(PERSONAL INFORMATION|EDUCATION|WORK EXPERIENCE|SKILLS|PROJECTS)", text, flags=re.I)
    # pieces like: before, header, content, header, content...
    out = {}
    i = 0
    while i < len(pieces):
        part = pieces[i].strip()
        if part.upper() in [h for h in SECTION_HEADERS]:
            header = part.upper()
            content = pieces[i+1] if i+1 < len(pieces) else ""
            out[header] = [l for l in content.splitlines() if l.strip() != ""]
            i += 2
        else:
            i += 1

    parsed = {}
    if "PERSONAL INFORMATION" in out:
        parsed["personal"] = parse_personal(out["PERSONAL INFORMATION"])
    if "EDUCATION" in out:
        parsed["education"] = parse_education(out["EDUCATION"])
    if "WORK EXPERIENCE" in out:
        parsed["work_experience"] = parse_work_experience(out["WORK EXPERIENCE"])
    if "SKILLS" in out:
        parsed["skills"] = out["SKILLS"]
    if "PROJECTS" in out:
        parsed["projects"] = out["PROJECTS"]
    return parsed
