import base64
import importlib.util
import io
import json
from pathlib import Path
import struct
import tempfile
import unittest
from unittest.mock import patch
from email.message import Message


spec = importlib.util.spec_from_file_location(
    "flutter_artifact", Path(__file__).resolve().parents[1] / "download_flutter_artifact.py"
)
artifact = importlib.util.module_from_spec(spec)
spec.loader.exec_module(artifact)


class FlutterArtifactTest(unittest.TestCase):
    def test_crc32c_matches_standard_vector(self):
        crc = artifact.update_crc32c(0xFFFFFFFF, b"123456789") ^ 0xFFFFFFFF
        self.assertEqual(crc, 0xE3069283)

    def test_composite_google_object_without_md5_is_verified_by_crc32c(self):
        response = io.BytesIO(b"123456789")
        response.headers = Message()
        response.headers["x-goog-hash"] = "crc32c=" + base64.b64encode(struct.pack(">I", 0xE3069283)).decode()
        response.headers["Content-Length"] = "9"
        with tempfile.TemporaryDirectory() as directory, patch.object(artifact.urllib.request, "urlopen", return_value=response):
            output = Path(directory) / "test.jar"
            artifact.download("https://storage.googleapis.com/download.flutter.io/test.jar", output, "engine", "test.jar")
            self.assertEqual(output.read_bytes(), b"123456789")
            record = json.loads(Path(str(output) + ".verified.json").read_text())
            self.assertIsNone(record["googleStorageMd5"])
            self.assertEqual(record["bytes"], 9)

    def test_bad_checksum_cannot_create_verified_artifact(self):
        response = io.BytesIO(b"changed")
        response.headers = Message()
        response.headers["x-goog-hash"] = "crc32c=AAAAAA=="
        with tempfile.TemporaryDirectory() as directory, patch.object(artifact.urllib.request, "urlopen", return_value=response):
            output = Path(directory) / "test.jar"
            with self.assertRaisesRegex(ValueError, "CRC32C mismatch"):
                artifact.download("https://storage.googleapis.com/download.flutter.io/test.jar", output, "engine", "test.jar")
            self.assertFalse(output.exists())
            self.assertFalse(Path(str(output) + ".verified.json").exists())


if __name__ == "__main__":
    unittest.main()
