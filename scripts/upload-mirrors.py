#!/usr/bin/env python3
"""
upload-mirrors.py - Upload built ISOs to fast mirrors and append download links to GITHUB_STEP_SUMMARY
Supported mirrors:
1. GoFile.io (High speed CDN, unlimited size)
2. Tmpfiles.org (Direct download link, up to 10GB)
3. Transfer.sh (Fallback)
"""

import os
import sys
import glob
import json
import subprocess
import urllib.request

def upload_gofile(file_path):
    try:
        req = urllib.request.Request("https://api.gofile.io/servers", headers={"User-Agent": "Mozilla/5.0"})
        with urllib.request.urlopen(req, timeout=15) as r:
            server = json.loads(r.read().decode())["data"]["servers"][0]["name"]
        
        upload_url = f"https://{server}.gofile.io/contents/uploadfile"
        cmd = ["curl", "-sS", "--max-time", "1800", "-F", f"file=@{file_path}", upload_url]
        res = subprocess.check_output(cmd).decode()
        data = json.loads(res)
        if data.get("status") == "ok":
            return data["data"]["downloadPage"]
    except Exception as e:
        print(f"GoFile upload error: {e}", file=sys.stderr)
    return None

def upload_tmpfiles(file_path):
    try:
        cmd = ["curl", "-sS", "--max-time", "1800", "-F", f"file=@{file_path}", "https://tmpfiles.org/api/v1/upload"]
        res = subprocess.check_output(cmd).decode()
        data = json.loads(res)
        if data.get("status") == "success":
            raw_url = data["data"]["url"]
            return raw_url.replace("tmpfiles.org/", "tmpfiles.org/dl/")
    except Exception as e:
        print(f"Tmpfiles upload error: {e}", file=sys.stderr)
    return None

def upload_transfersh(file_path):
    try:
        filename = os.path.basename(file_path)
        cmd = ["curl", "-sS", "--connect-timeout", "10", "--max-time", "1800", "--upload-file", file_path, f"https://transfer.sh/{filename}"]
        res = subprocess.check_output(cmd).decode().strip()
        if res.startswith("https://"):
            return res
    except Exception as e:
        print(f"Transfer.sh upload error: {e}", file=sys.stderr)
    return None

def main():
    dist_dir = sys.argv[1] if len(sys.argv) > 1 else "dist"
    iso_files = glob.glob(os.path.join(dist_dir, "*.iso"))
    if not iso_files:
        print(f"No .iso files found in {dist_dir}")
        sys.exit(0)

    summary_file = os.environ.get("GITHUB_STEP_SUMMARY")
    summary_lines = [
        "### 🚀 Fast Download Mirrors",
        "",
    ]

    for iso in iso_files:
        filename = os.path.basename(iso)
        size_mb = os.path.getsize(iso) / (1024 * 1024)
        print(f"\n==========================================")
        print(f"Uploading {filename} ({size_mb:.1f} MB)...")
        print(f"==========================================")
        summary_lines.append(f"#### 📦 {filename} ({size_mb:.1f} MB)")

        # 1. GoFile
        print("Uploading to GoFile...")
        gofile_link = upload_gofile(iso)
        if gofile_link:
            print(f"  --> GoFile URL: {gofile_link}")
            summary_lines.append(f"- ⚡ **GoFile (High Speed)**: {gofile_link}")
        else:
            print("  --> GoFile upload failed or unavailable.")

        # 2. Tmpfiles.org
        print("Uploading to Tmpfiles.org...")
        tmp_link = upload_tmpfiles(iso)
        if tmp_link:
            print(f"  --> Tmpfiles URL: {tmp_link}")
            summary_lines.append(f"- ⚡ **Tmpfiles.org (Direct)**: {tmp_link}")
        else:
            print("  --> Tmpfiles upload failed or unavailable.")

        # 3. Transfer.sh
        print("Uploading to transfer.sh...")
        tsh_link = upload_transfersh(iso)
        if tsh_link:
            print(f"  --> Transfer.sh URL: {tsh_link}")
            summary_lines.append(f"- ⚡ **transfer.sh**: {tsh_link}")

        summary_lines.append("")

    if summary_file:
        try:
            with open(summary_file, "a", encoding="utf-8") as f:
                f.write("\n".join(summary_lines) + "\n")
            print("Written links to GITHUB_STEP_SUMMARY successfully.")
        except Exception as e:
            print(f"Failed to write GITHUB_STEP_SUMMARY: {e}", file=sys.stderr)

    print("\nUpload complete! Summary:")
    print("\n".join(summary_lines))

if __name__ == "__main__":
    main()
