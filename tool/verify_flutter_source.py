#!/usr/bin/env python3
"""Fail closed when the reviewed Flutter source is incomplete or regresses."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
FLUTTER = ROOT / "flutter"
REQUIRED = (
    "pubspec.yaml",
    "lib/main.dart",
    "lib/data/database.dart",
    "lib/models/catalog.dart",
    "lib/services/api.dart",
    "lib/services/app_services.dart",
    "lib/services/cover_cache.dart",
    "lib/services/download.dart",
    "lib/services/session_vault.dart",
    "lib/ui/catalog_page.dart",
    "lib/ui/cover_image.dart",
    "lib/ui/lume_theme.dart",
    "lib/ui/login_page.dart",
    "lib/ui/work_detail_page.dart",
    "lib/ui/signup_page.dart",
    "lib/ui/admin_users_page.dart",
    "lib/ui/admin_catalog_page.dart",
    "lib/readers/reader_factory.dart",
)


def main() -> int:
    missing = [path for path in REQUIRED if not (FLUTTER / path).is_file()]
    if missing:
        raise SystemExit(f"missing reviewed Flutter source: {', '.join(missing)}")

    pubspec = (FLUTTER / "pubspec.yaml").read_text(encoding="utf-8")
    if "version: 0.40.0+40" not in pubspec:
        raise SystemExit("unexpected LUME candidate version")

    catalog = (FLUTTER / "lib/models/catalog.dart").read_text(encoding="utf-8")
    for marker in ("class CoverAsset", "final CoverAsset? cover", "'magazine'"):
        if marker not in catalog:
            raise SystemExit(f"catalog cover contract missing marker: {marker}")

    dart_files = sorted((FLUTTER / "lib").rglob("*.dart"))
    if len(dart_files) < 35:
        raise SystemExit(f"unexpectedly small Flutter source tree: {len(dart_files)} files")
    digest = hashlib.sha256()
    for path in dart_files:
        relative = path.relative_to(ROOT).as_posix().encode()
        data = path.read_bytes()
        digest.update(len(relative).to_bytes(4, "big"))
        digest.update(relative)
        digest.update(len(data).to_bytes(8, "big"))
        digest.update(data)
    print(json.dumps({
        "ok": True,
        "sourceMode": "direct-reviewed",
        "dartFiles": len(dart_files),
        "sourceTreeSha256": digest.hexdigest(),
    }, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
