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
tabs = read('lib/app/main_tab.dart')
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
# V8 moved the product tab labels into a single constant used by every
# shell. The enum's internal 'browse' name is retained for persisted state,
# while the second *visible* destination must be called New.
expected_tabs = ['Home', 'New', 'Library', 'Search']
match = re.search(
    r'const\s+List<String>\s+breezzeMainTabLabels\s*=\s*<String>\[(.*?)\];',
    tabs,
    re.DOTALL,
)
if match is None:
    issues.append('missing V8 canonical navigation labels in main_tab.dart')
else:
    declared_tabs = re.findall(r"'([^']+)'", match.group(1))
    if declared_tabs != expected_tabs:
        issues.append(
            f'wrong primary navigation order: {declared_tabs!r}; '
            f'expected {expected_tabs!r}'
        )
    # Keep semantics and tab labels driven by ONE list. Hardcoded legacy
    # labels can pass static checks but still mismatch the mobile UI.
    for index, tab in enumerate(expected_tabs):
        if not re.search(
            rf'_TabDestination\(breezzeMainTabLabels\[{index}\]\s*,',
            shell,
        ):
            issues.append(f'missing canonical shell destination: {tab}')
if re.search(r"_TabDestination\('Browse'\s*,", shell):
    issues.append('legacy Browse label found; visible tab must be New')
# Heartbeat/sleep timers are legitimate. Reject only the legacy fake player
# pattern that advances elapsed audio position from a clock tick.
if re.search(r'(?s)Timer\.periodic\s*\(.{0,900}?\b(?:_position|position)\s*\+=', player):
    issues.append('player_controller.dart must not fake playback position with a periodic timer')

if issues:
    print('Breezze identity contract FAILED:')
    for issue in issues:
        print(f' - {issue}')
    sys.exit(1)
print('Breezze identity contract OK (static contract, not runtime verification)')
