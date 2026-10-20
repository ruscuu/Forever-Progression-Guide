"""Importa las observaciones que el addon guarda mientras juegas.

El addon anota en sus SavedVariables las instancias en las que entras, sus
mapas, los jefes derrotados y las misiones aceptadas o entregadas. Este script
las convierte en un archivo de data-sources/contributions/ que build_data.py
fusiona como datos `verified_ingame`.

No se guardan nombres de personaje, reino ni cuenta: solo datos del juego.

Uso (Windows):
    python pipeline\\import_contributions.py "C:\\...\\WTF\\Account\\MICUENTA\\SavedVariables\\ForeverProgressionGuide.lua"
    python pipeline\\import_contributions.py --wow "C:\\Program Files (x86)\\World of Warcraft\\_classic_beta_"
"""

import argparse
import hashlib
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from luatable import parse_assignments  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
CONTRIB_DIR = ROOT / "data-sources" / "contributions"
SAVED_VAR = "ForeverProgressionGuideDB"


def keys_of(table):
    """Convierte un conjunto Lua ({[x] = true}) o una lista en lista."""
    if isinstance(table, dict):
        return sorted(k for k, v in table.items() if v)
    return list(table or [])


def normalize(contrib):
    instances = {}
    for instance_id, obs in (contrib.get("instances") or {}).items():
        instances[str(instance_id)] = {
            "name": obs.get("name"),
            "locale": obs.get("locale"),
            "type": obs.get("type"),
            "maxPlayers": obs.get("maxPlayers"),
            "uiMapIDs": keys_of(obs.get("uiMapIDs")),
            "levels": {str(k): v for k, v in (obs.get("levels") or {}).items()},
            "encounters": {str(k): {"name": v.get("name")} for k, v in (obs.get("encounters") or {}).items()},
            "entrance": obs.get("entrance"),
        }
    quests = {str(k): {f: v.get(f) for f in ("level", "mapID", "xp") if v.get(f) is not None}
              for k, v in (contrib.get("quests") or {}).items()}
    return {"builds": keys_of(contrib.get("builds")), "instances": instances, "quests": quests}


def normalize_translations(translations):
    """Nombres recogidos con /wfg traducir: {locale: {items: {id: nombre}, quests: {...}}}."""
    out = {}
    for locale, data in (translations or {}).items():
        out[locale] = {kind: {str(k): v for k, v in (data.get(kind) or {}).items()} for kind in ("items", "quests")}
    return out


def import_file(path):
    variables = parse_assignments(Path(path).read_text(encoding="utf-8", errors="replace"))
    db = variables.get(SAVED_VAR)
    if not isinstance(db, dict) or not (db.get("contributions") or db.get("translations")):
        raise SystemExit(f"{path}: no contiene observaciones de {SAVED_VAR}. ¿Has jugado con el addon activado?")
    data = normalize(db.get("contributions") or {})
    translations = normalize_translations(db.get("translations"))
    if translations:
        data["translations"] = translations
    text = json.dumps(data, indent=2, ensure_ascii=False, sort_keys=True) + "\n"
    # El nombre depende del contenido: importar dos veces lo mismo no duplica archivos.
    out = CONTRIB_DIR / f"{hashlib.sha256(text.encode()).hexdigest()[:12]}.json"
    CONTRIB_DIR.mkdir(parents=True, exist_ok=True)
    out.write_text(text, encoding="utf-8", newline="\n")
    names = sum(len(t["items"]) + len(t["quests"]) for t in data.get("translations", {}).values())
    print(f"{out.relative_to(ROOT)}: {len(data['instances'])} instancias, {len(data['quests'])} misiones, {names} nombres traducidos.")
    return out


def find_saved_variables(wow_dir):
    return sorted(Path(wow_dir).glob(f"WTF/Account/*/SavedVariables/ForeverProgressionGuide.lua"))


def main(argv=None):
    parser = argparse.ArgumentParser(description="Importa observaciones del addon.")
    parser.add_argument("files", nargs="*", help="archivos ForeverProgressionGuide.lua de SavedVariables")
    parser.add_argument("--wow", help="carpeta del cliente (la que contiene WTF\\)")
    args = parser.parse_args(argv)

    files = list(args.files) + (find_saved_variables(args.wow) if args.wow else [])
    if not files:
        parser.error("indica un archivo de SavedVariables o la carpeta del cliente con --wow")
    for f in files:
        import_file(f)
    print("Ahora ejecuta: python pipeline/build_data.py")


if __name__ == "__main__":
    main()
