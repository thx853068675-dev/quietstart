#!/usr/bin/env python3
"""Fetch the pinned public HAP, including after assets are consolidated."""
from pathlib import Path
from urllib.request import urlopen
from urllib.error import HTTPError
import hashlib
import io
import zipfile
from prepare import HAP_SHA

BASE = 'https://github.com/thx853068675-dev/quietstart/releases/download/v0.9.43/'
try:
    with urlopen(BASE + 'quietstart-0.9.43-precompiled.hap', timeout=60) as response:
        data = response.read(64 * 1024 * 1024)
except HTTPError as error:
    if error.code != 404:
        raise
    # The published release has one complete download per desktop platform.
    with urlopen(BASE + 'quietstart-0.9.43-macOS-arm64-bundle.zip', timeout=120) as response:
        bundle = response.read(256 * 1024 * 1024)
    with zipfile.ZipFile(io.BytesIO(bundle)) as archive:
        candidates = [i for i in archive.infolist()
                      if i.filename.endswith('/quietstart-0.9.43.hap')]
        if len(candidates) != 1 or candidates[0].file_size > 64 * 1024 * 1024:
            raise ValueError('Expected one bounded root HAP in the combined bundle')
        data = archive.read(candidates[0])
if hashlib.sha256(data).hexdigest() != HAP_SHA:
    raise ValueError('QuietStart HAP digest mismatch')
Path('quietstart.hap').write_bytes(data)
print('Downloaded pinned QuietStart HAP; SHA-256 verified')
