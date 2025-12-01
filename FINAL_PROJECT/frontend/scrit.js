const form = document.getElementById("uploadForm");
const responseBox = document.getElementById("response");

form.addEventListener("submit", async (e) => {
    e.preventDefault();
    const fileInput = document.getElementById("resumeFile");
    const file = fileInput.files[0];
    if (!file) return;

    const formData = new FormData();
    formData.append("file", file);

    responseBox.textContent = "Uploading...";

    try {
        const res = await fetch("/upload", {
            method: "POST",
            body: formData
        });

        const data = await res.json();
        responseBox.textContent = JSON.stringify(data, null, 2);
    } catch (err) {
        responseBox.textContent = "Error: " + err.message;
    }
});

