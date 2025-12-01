const form = document.getElementById("uploadForm");
const responseBox = document.getElementById("response");


document.getElementById("uploadBtn").addEventListener("click", async () => {
  const file = document.getElementById("fileInput").files[0];
  if (!file) {
    document.getElementById("status").innerText = "Choose a file first.";
    return;
  }
  const form = new FormData();
  form.append("file", file);
  document.getElementById("status").innerText = "Uploading...";
  const res = await fetch("/upload", { method: "POST", body: form });
  const data = await res.json();
  if (res.ok) {
    document.getElementById("status").innerText = "Uploaded successfully.";
    document.getElementById("result").innerText = JSON.stringify(data, null, 2);
  } else {
    document.getElementById("status").innerText = "Upload error: " + (data.error || res.statusText);
  }
});
