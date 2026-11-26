#!/usr/bin/env python3
"""V8 UI source-of-truth guard: one shell, brand, glass engine and tab set.

This checks structural constraints only; it does not claim pixel parity,
platform certification or licensed music delivery. Paths only, no secrets.
"""
from __future__ import annotations

import re
from pathlib import Path


REPO = Path(__file__).resolve().parents[1]
SHELL = "apps/mobile/lib/widgets/bz_shell.dart"
TABS = "apps/mobile/lib/app/main_tab.dart"
THEME = "packages/design_system/lib/bz_theme.dart"
GLASS_CORE = "packages/design_system/lib/src/glass/bz_glass.dart"
GLASS_ADAPTER = "packages/design_system/lib/src/bz_glass_container.dart"
BRAND = "apps/mobile/lib/widgets/bz_brand_icons.dart"
MORPH = "apps/mobile/lib/widgets/bz_morphing_brand_header.dart"
MOOD = "apps/mobile/lib/widgets/bz_pinned_mood_rail.dart"
DETAIL_BAR = "apps/mobile/lib/widgets/bz_branded_app_bar.dart"
BROWSE = "apps/mobile/lib/features/browse/browse_screen.dart"
PROVIDER = "apps/mobile/lib/features/browse/ytmusic_client_screen.dart"
PRIMARY_PAGES = (
    "apps/mobile/lib/features/home/home_screen.dart",
    "apps/mobile/lib/features/browse/browse_screen.dart",
    "apps/mobile/lib/features/library/library_screen.dart",
    "apps/mobile/lib/features/search/search_screen.dart",
)
SECONDARY_PAGES = (
    "apps/mobile/lib/features/library/playlist_detail_screen.dart",
    "apps/mobile/lib/features/catalog/catalog_detail_screens.dart",
    "apps/mobile/lib/features/catalog/spotify_artist_screen.dart",
    "apps/mobile/lib/features/settings/account_screen.dart",
    "apps/mobile/lib/features/notifications/notifications_screen.dart",
    "apps/mobile/lib/features/video/official_music_video_screen.dart",
)


def violations(root: Path = REPO) -> list[str]:
    issues: list[str] = []
    content: dict[str, str] = {}
    for name in (SHELL, TABS, THEME, GLASS_CORE, GLASS_ADAPTER, BRAND,
                 MORPH, MOOD, DETAIL_BAR, BROWSE, PROVIDER, *PRIMARY_PAGES,
                 *SECONDARY_PAGES):
        p = root / name
        if not p.is_file():
            issues.append(f"MISSING_UI_SOURCE: {name}")
            continue
        content[name] = p.read_text(encoding="utf-8")

    def has(name: str, pattern: str, code: str):
        text = content.get(name)
        if text is not None and not re.search(pattern, text):
            issues.append(f"{code}: {name}")

    has(TABS, r"'Home'\s*,\s*'New'\s*,\s*'Library'\s*,\s*'Search'", "FOUR_TAB_CONTRACT")
    has(SHELL, r"IndexedStack\(", "ONE_SHELL_MISSING")
    has(SHELL, r"BzGlassBudgetScope", "SHELL_GLASS_BUDGET_MISSING")
    has(THEME, r"export 'src/bz_theme\.dart'", "THEME_DUPLICATE_SOURCE")
    has(GLASS_CORE, r"BackdropFilter\(", "CANONICAL_GLASS_MISSING")
    has(GLASS_ADAPTER, r"return BzGlass\(", "GLASS_FACADE_NOT_DELEGATED")
    has(BRAND, r"class BzBnoteMark", "ORIGINAL_BRAND_MISSING")
    has(MORPH, r"class BzMorphingBrandHeader", "MORPH_HEADER_MISSING")
    has(MORPH, r"BzBnoteMark", "MORPH_OWN_SYMBOL_MISSING")
    has(MOOD, r"class BzPinnedMoodRail", "PINNED_MOOD_SOURCE_MISSING")
    has(PRIMARY_PAGES[0], r"BzPinnedMoodRail\(", "HOME_PINNED_MOODS_MISSING")
    has(BROWSE, r"featuredDestinations", "FEATURED_NEW_SECTIONS_MISSING")
    has(BROWSE, r"otherDestinations", "NEW_DUPLICATE_DESTINATIONS")
    has(DETAIL_BAR, r"class BzBrandedAppBar", "UNIFIED_DETAIL_BAR_MISSING")
    has(DETAIL_BAR, r"BzCompactBrandMark", "UNIFIED_BRAND_MISSING")
    has(BROWSE, r"YouTubeMusicClientScreen\(", "YT_CATALOG_NOT_IN_NEW")
    has(PROVIDER, r"BzBrandedAppBar", "PROVIDER_OLD_BRANDING")

    for page in PRIMARY_PAGES:
        source = content.get(page, "")
        if source and "BzMorphingBrandHeader(" not in source:
            issues.append("OLD_PAGE_HEADER: " + page)
        if source and "BzCompactBrandMark(" in source:
            issues.append("DUPLICATE_PAGE_BRAND: " + page)

    home = content.get(PRIMARY_PAGES[0], "")
    if home and home.count("BzPinnedMoodRail(") != 1:
        issues.append("DUPLICATE_HOME_MOOD_RAIL: " + PRIMARY_PAGES[0])

    old_glass = content.get(GLASS_ADAPTER, "")
    if re.search(r"\bBackdropFilter\s*\(|\bImageFilter\.blur\s*\(", old_glass):
        issues.append("SECOND_GLASS_RENDERER: " + GLASS_ADAPTER)

    shell = content.get(SHELL, "")
    if re.search(r"\bYouTubeMusicClientScreen\b", shell):
        issues.append("DUPLICATE_PROVIDER_TAB: " + SHELL)

    provider = content.get(PROVIDER, "")
    if re.search(r"appBar:\s*AppBar\(", provider):
        issues.append("LEGACY_PROVIDER_TOOLBAR: " + PROVIDER)

    for page in SECONDARY_PAGES:
        source = content.get(page, "")
        if source and re.search(r"appBar:\s*AppBar\(", source):
            issues.append("LEGACY_DETAIL_TOOLBAR: " + page)
        if source and "BzBrandedAppBar" not in source:
            issues.append("UNBRANDED_SECONDARY_PAGE: " + page)

    # Reference source may inform screen hierarchy; no external clone code
    # is vendored into Flutter's production UI.
    if (root / "apps/mobile/lib/ytm_ui_clone").exists():
        issues.append("VENDORED_UNLICENSED_UI_SOURCE")
    return issues


def main() -> int:
    issues = violations()
    for issue in issues:
        print(issue)
    print("V8_UI_SINGLE_SOURCE: " + ("PASS" if not issues else "FAIL"))
    return 1 if issues else 0


if __name__ == "__main__":
    raise SystemExit(main())
