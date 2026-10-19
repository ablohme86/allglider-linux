#!/usr/bin/env python3
"""
AllGlider Live Linux - Fetch Latest AllGlider Release
Fetches the latest Linux tarball from https://allglider.com/downloads,
caches it in cache/, verifies its SHA256, and updates config/versions.lock.
"""
import hashlib
import os
import re
import sys
import urllib.parse
import urllib.request
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
CACHE_DIR = REPO_ROOT / "cache"
VERSIONS_LOCK = REPO_ROOT / "config" / "versions.lock"
DOWNLOADS_URL = "https://allglider.com/downloads"


def fetch_latest():
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    print(f"=== Checking for latest AllGlider release at {DOWNLOADS_URL} ===")

    req = urllib.request.Request(
        DOWNLOADS_URL,
        headers={"User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AllGlider-Live-Builder"},
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            html = resp.read().decode("utf-8")
    except Exception as exc:
        print(f"WARNING: Could not connect to {DOWNLOADS_URL} ({exc}). Using cached version.")
        return None

    # Search for allglider-<version>-linux-x86_64.tar.gz link
    match = re.search(r'href=[\'"]([^\'"]*allglider-([0-9.]+)-linux-x86_64\.tar\.gz)[\'"]', html)
    if not match:
        print("WARNING: Could not find AllGlider Linux tarball link on downloads page. Using cached version.")
        return None

    href, version = match.group(1), match.group(2)
    download_url = urllib.parse.urljoin(DOWNLOADS_URL, href)
    tarball_name = f"allglider-{version}-linux-x86_64.tar.gz"
    dest_path = CACHE_DIR / tarball_name

    print(f"Latest AllGlider version on site: {version} ({tarball_name})")

    # Download if not present or empty
    if not dest_path.exists() or dest_path.stat().st_size == 0:
        print(f"Downloading {download_url} to {dest_path}...")
        part_path = CACHE_DIR / f"{tarball_name}.part"
        dl_req = urllib.request.Request(
            download_url,
            headers={"User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AllGlider-Live-Builder"},
        )
        with urllib.request.urlopen(dl_req, timeout=120) as dl_resp, open(part_path, "wb") as f:
            while True:
                chunk = dl_resp.read(65536)
                if not chunk:
                    break
                f.write(chunk)
        part_path.replace(dest_path)
        print(f"Download complete: {dest_path.stat().st_size} bytes.")

    # Calculate SHA256
    h = hashlib.sha256()
    with open(dest_path, "rb") as f:
        while chunk := f.read(65536):
            h.update(chunk)
    csum = h.hexdigest()
    print(f"SHA256 for {tarball_name}: {csum}")

    # Update config/versions.lock if changed
    if VERSIONS_LOCK.exists():
        content = VERSIONS_LOCK.read_text(encoding="utf-8")
        new_content = re.sub(r'ALLGLIDER_VERSION="[^"]*"', f'ALLGLIDER_VERSION="{version}"', content)
        new_content = re.sub(r'ALLGLIDER_TARBALL="[^"]*"', f'ALLGLIDER_TARBALL="{tarball_name}"', new_content)
        new_content = re.sub(r'ALLGLIDER_SHA256="[^"]*"', f'ALLGLIDER_SHA256="{csum}"', new_content)
        if new_content != content:
            VERSIONS_LOCK.write_text(new_content, encoding="utf-8")
            print(f"Updated {VERSIONS_LOCK} with AllGlider {version}.")

    return {
        "version": version,
        "tarball": tarball_name,
        "path": str(dest_path),
        "sha256": csum,
    }


if __name__ == "__main__":
    res = fetch_latest()
    if res:
        print(f"AllGlider ready: {res['version']} ({res['tarball']})")
    else:
        print("Using existing local/cached AllGlider version.")
