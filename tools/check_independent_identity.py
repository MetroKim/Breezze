#!/usr/bin/env python3
"""Fail CI if the canonical Breezze Flutter app regresses to a legacy fork scaffold.

Only active Flutter package and playback entrypoints are checked. Historical
attribution in notices and migration documents is not a failure.
"""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / 'apps' / 'mobile'
issues = []


def read(relative):
    path = APP / relative
    if not path.is_file():
        issues.append(f'missing canonical app file: {path.relative_to(ROOT)}')
        return ''
    return path.read_text(encoding='utf-8')


pubspec = read('pubspec.yaml')
main = read('lib/main.dart')
shell = read('lib/widgets/bz_shell.dart')
root = read('lib/widgets/breezze_app_root.dart')
player = read('lib/features/player/player_controller.dart')

if not re.search(r'(?m)^name:\s*breezze\s*$', pubspec):
    issues.append('apps/mobile/pubspec.yaml must declare name: breezze')
for path, contents in [
    ('pubspec.yaml', pubspec), ('lib/main.dart', main),
    ('lib/widgets/bz_shell.dart', shell),
    ('lib/widgets/breezze_app_root.dart', root),
    ('lib/features/player/player_controller.dart', player),
]:
    if re.search(r'(?i)\b(?:bit.?chord|metro.?music|bitchord_flutter)\b', contents):
        issues.append(f'legacy application identity in active entrypoint: {path}')

if 'BreezzeAppRoot' not in main:
    issues.append('main.dart must launch the canonical BreezzeAppRoot')
if 'BreezzeShell' not in root:
    issues.append('BreezzeAppRoot must launch the canonical BreezzeShell')
for tab in ('Home', 'Browse', 'Library', 'Search'):
    if not re.search(rf"_TabDestination\('{tab}'\s*,", shell):
        issues.append(f'missing canonical tab: {tab}')
if re.search(r'\bTimer\.periodic\s*\(', player):
    issues.append('player_controller.dart must not simulate playback position using Timer.periodic')

if issues:
    print('Breezze identity contract FAILED:')
    for issue in issues:
        print(f' - {issue}')
    sys.exit(1)
print('Breezze identity contract OK (static contract, not runtime verification)')
