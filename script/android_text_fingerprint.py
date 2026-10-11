#!/usr/bin/env python3
"""Stable source fingerprint: file names + contents, independent of clone timestamps."""
import hashlib
from pathlib import Path

root = Path(__file__).resolve().parents[1] / 'AndroidTextService' / 'src'
digest = hashlib.sha256()
for source in sorted(root.rglob('*.java')):
    digest.update(source.relative_to(root).as_posix().encode('utf-8'))
    digest.update(b'\0')
    digest.update(source.read_bytes())
    digest.update(b'\0')
print(digest.hexdigest())
