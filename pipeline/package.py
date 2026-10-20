"""Empaqueta el addon en un .zip listo para instalar o publicar.

Uso:
    python pipeline/package.py 2026.10.20-1c2f9a
Resultado: release/WoWForeverGuide-<versión>.zip con la carpeta WoWForeverGuide/.
"""

import argparse
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ADDON = ROOT / "WoWForeverGuide"
RELEASE_DIR = ROOT / "release"


def package(version):
    RELEASE_DIR.mkdir(exist_ok=True)
    out = RELEASE_DIR / f"WoWForeverGuide-{version}.zip"
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as zf:
        for path in sorted(ADDON.rglob("*")):
            if path.is_dir():
                continue
            arcname = Path("WoWForeverGuide") / path.relative_to(ADDON)
            data = path.read_bytes()
            if path.suffix == ".toc":
                data = data.replace(b"@project-version@", version.encode())
            # Fecha fija: el mismo contenido produce el mismo zip.
            info = zipfile.ZipInfo(arcname.as_posix(), date_time=(2026, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            zf.writestr(info, data)
    print(out.relative_to(ROOT))
    return out


def main(argv=None):
    parser = argparse.ArgumentParser(description="Empaqueta el addon.")
    parser.add_argument("version")
    package(parser.parse_args(argv).version)


if __name__ == "__main__":
    main()
