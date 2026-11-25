# Breezze — legacy design handoff index

All original user-supplied artwork is preserved **byte-for-byte** in a single
canonical archive at [`docs/design/reference/`](../reference/README.md).

This folder remains as a stable historical index. Its former `originals/`
directory and two text export specifications were removed from the active tree
only after confirming identical Git blob hashes for every file in the canonical
reference archive. Their history remains in Git.

## Exact original files (canonical paths)

- [Frontend Figma import pack](../reference/Breezze_Frontend_Figma_Import_Pack.zip) — 16 screen SVGs, combined board, PNG preview and README.
- [Flutter UI reference](../reference/breezze_flutter_ui_reference.zip) — visual-only sample. Its mocked player and sample data must never replace Breezze's real runtime.
- [Historical branding boards](../reference/historical-brand/) — three original PNGs.
- [Glass Disc export specification](../reference/historical-concepts/GLASS_DISC_EXPORT_SPEC.md) and [Drift export specification](../reference/historical-concepts/DRIFT_EXPORT_SPEC.md) — competing historical design concepts, not shipping icons.

The selected production identity remains **white mark on black** in
`apps/mobile/assets/icons/`. There is still only one Flutter app and one
player. The four primary tabs remain Home, Browse, Library, and Search.

The supported verification command remains:
`python3 apps/mobile/tool/verify_legacy_design_handoff.py`.
It delegates archive/brand checksum verification to
`tools/verify_design_handoff_archives.py` and additionally parses the active
monochrome Breezze SVG lockups. Both paths continue to run in CI.
