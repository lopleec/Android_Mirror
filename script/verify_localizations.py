#!/usr/bin/env python3
"""Check catalog syntax, translated keys, format placeholders and source coverage."""
import json
import re
import sys
from collections import Counter
from pathlib import Path

root = Path(__file__).resolve().parents[1]
quoted = r'"(?:[^"\\]|\\.)*"'
entry = re.compile(rf'^\s*({quoted})\s*=\s*({quoted})\s*;\s*$', re.MULTILINE)
placeholder = re.compile(r'%(?:\d+\$)?(?:ld|d|u|@|f|s)')
errors = []

def catalog(path):
    text = path.read_text()
    values = {}
    for key, value in entry.findall(text):
        key, value = json.loads(key), json.loads(value)
        if key in values:
            errors.append(f'{path.relative_to(root)}: duplicate key {key!r}')
        values[key] = value
    for line in text.splitlines():
        if line.strip() and not line.lstrip().startswith('//') and not entry.fullmatch(line):
            errors.append(f'{path.relative_to(root)}: invalid entry {line!r}')
    return values

english = catalog(root / 'Sources/AndroidMirror/Localization/en.lproj/Localizable.strings')
chinese = catalog(root / 'Sources/AndroidMirror/Localization/zh-Hans.lproj/Localizable.strings')
for language, values in [('en', english), ('zh-Hans', chinese)]:
    for key in set(english) ^ set(values):
        errors.append(f'{language}: missing or extra key {key!r}')
    for key, value in values.items():
        if not value or Counter(placeholder.findall(key)) != Counter(placeholder.findall(value)):
            errors.append(f'{language}: empty value or mismatched placeholders for {key!r}')

call = re.compile(rf'L10n\.(?:tr|format)\(\s*({quoted})')
# App-owned visible literals must go through the localization boundary. Symbols,
# dynamic device names, protocol bytes and telemetry are intentionally unaffected.
for source in (root / 'Sources/AndroidMirror').rglob('*.swift'):
    text = source.read_text()
    for key in call.findall(text):
        if json.loads(key) not in english:
            errors.append(f'{source.relative_to(root)}: uncatalogued key {key}')
    for literal in re.findall(quoted, text):
        if re.search(r'[\u3400-\u9fff]', literal):
            errors.append(f'{source.relative_to(root)}: unlocalized Chinese literal {literal}')
for language in ['en', 'zh-Hans']:
    values = catalog(root / f'Assets/Localization/{language}.lproj/InfoPlist.strings')
    for key in ['CFBundleName', 'CFBundleDisplayName', 'NSLocalNetworkUsageDescription']:
        if key not in values:
            errors.append(f'{language}: missing bundle localization {key}')
    if not (root / f'Sources/AndroidMirror/Resources/Guide-{language}.html').is_file():
        errors.append(f'{language}: localized help guide is missing')
if errors:
    print('\n'.join(errors), file=sys.stderr)
    sys.exit(1)
print(f'Localization check passed: {len(english)} keys in English and Simplified Chinese.')
