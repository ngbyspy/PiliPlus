"""Cache official Flutter Maven artifacts after checking Google's transfer hash."""

import argparse
import base64
import hashlib
import json
from pathlib import Path
import struct
import time
import urllib.error
import urllib.request


def crc32c_table():
    result = []
    for value in range(256):
        for _ in range(8):
            value = (value >> 1) ^ (0x82F63B78 if value & 1 else 0)
        result.append(value)
    return result


CRC_TABLE = crc32c_table()


def update_crc32c(crc, block):
    for value in block:
        crc = CRC_TABLE[(crc ^ value) & 0xFF] ^ (crc >> 8)
    return crc


def download(url, output, engine, relative):
    if not url.startswith("https://storage.googleapis.com/download.flutter.io/"):
        raise ValueError("Only the official Flutter Maven source is allowed")
    output = Path(output)
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = output.with_suffix(output.suffix + ".partial")
    with urllib.request.urlopen(url, timeout=60) as response:
        hashes = dict(
            value.strip().split("=", 1)
            for header in response.headers.get_all("x-goog-hash", [])
            for value in header.split(",")
            if "=" in value
        )
        if not (hashes.get("md5") or hashes.get("crc32c")):
            raise ValueError("Official response has no supported transfer hash")
        md5 = hashlib.md5()
        sha256 = hashlib.sha256()
        crc = 0xFFFFFFFF
        length = 0
        with temporary.open("wb") as stream:
            while block := response.read(1024 * 1024):
                stream.write(block)
                md5.update(block)
                sha256.update(block)
                if hashes.get("crc32c"):
                    crc = update_crc32c(crc, block)
                length += len(block)
        advertised = response.headers.get("Content-Length")
        if advertised and length != int(advertised):
            raise ValueError("Flutter artifact length mismatch")
        if hashes.get("md5") and base64.b64encode(md5.digest()).decode() != hashes["md5"]:
            raise ValueError("Flutter artifact MD5 mismatch")
        actual_crc = base64.b64encode(struct.pack(">I", crc ^ 0xFFFFFFFF)).decode()
        if hashes.get("crc32c") and actual_crc != hashes["crc32c"]:
            raise ValueError("Flutter artifact CRC32C mismatch")
    temporary.replace(output)
    record = {
        "url": url,
        "sha256": sha256.hexdigest(),
        "googleStorageMd5": hashes.get("md5"),
        "googleStorageCrc32c": hashes.get("crc32c"),
        "engineCommit": engine,
        "file": relative,
        "bytes": length,
    }
    Path(str(output) + ".verified.json").write_text(
        json.dumps(record, indent=2) + "\n", encoding="utf-8"
    )
    return record


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    for name in ("url", "output", "engine", "relative"):
        parser.add_argument("--" + name, required=True)
    args = parser.parse_args()
    for attempt in range(3):
        try:
            result = download(args.url, args.output, args.engine, args.relative)
            print(f"Verified Flutter artifact: {result['file']} ({result['bytes']} bytes)")
            break
        except (urllib.error.URLError, TimeoutError, ConnectionError):
            if attempt == 2:
                raise
            time.sleep(2)
