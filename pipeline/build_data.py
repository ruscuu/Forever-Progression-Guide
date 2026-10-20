"""Genera los datos del addon a partir de todas las fuentes.

Orden de fusión (de menor a mayor prioridad, campo a campo):
  1. data-sources/seed/          datos semilla (heredados de Classic)
  2. fuentes externas importadas  solo si sources.json marca redistribution_allowed
  3. data-sources/contributions/  observaciones hechas dentro del juego

Un campo solo se sustituye por otro de igual o mayor confianza. Cada campo
recuerda su procedencia, y los cambios respecto a la versión anterior se
escriben en validation/changes-latest.md para revisarlos (plan §12.D).

Uso:
    python pipeline/build_data.py           # regenera
    python pipeline/build_data.py --check   # falla si los archivos generados no están al día
"""

import argparse
import copy
import datetime as dt
import hashlib
import json
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from luatable import to_lua  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
SEED_DIR = ROOT / "data-sources" / "seed"
CONTRIB_DIR = ROOT / "data-sources" / "contributions"
RAW_DIR = ROOT / "data-sources" / "raw"
SOURCES_FILE = ROOT / "data-sources" / "sources.json"
SNAPSHOT_DIR = ROOT / "data-sources" / "generated"
ADDON_DATA_DIR = ROOT / "WoWForeverGuide" / "Data"
REPORT_FILE = ROOT / "validation" / "changes-latest.md"

STATUS_RANK = {"unknown": 0, "announced": 1, "classic_inherited": 2, "datamined": 3, "verified_ingame": 4}
DUNGEON_TYPES = {"dungeon", "raid"}
FACTIONS = {"both", "alliance", "horde"}
MAX_LEVEL = 60  # límite de validación, no de juego: se sube si Forever amplía el nivel máximo
TRACKED_FIELDS = ("name", "zone", "levels", "bosses", "wings", "size", "type", "faction")
LUA_HEADER = "-- Generado por pipeline/build_data.py a partir de data-sources/. No editar a mano.\nlocal _, ns = ...\nns.Data = ns.Data or {}\n"


class ValidationError(Exception):
    pass


# ---------------------------------------------------------------- utilidades

def get_path(obj, path):
    for part in path.split("."):
        if not isinstance(obj, dict) or part not in obj:
            return None
        obj = obj[part]
    return obj


def set_path(obj, path, value):
    parts = path.split(".")
    for part in parts[:-1]:
        obj = obj.setdefault(part, {})
    obj[parts[-1]] = value


def build_key(build):
    return tuple(int(x) if x.isdigit() else 0 for x in str(build).split("."))


def lang_of(locale):
    return "es" if str(locale).startswith("es") else "en"


def apply_field(record, field, value, status, source):
    """Escribe un campo si la nueva procedencia es al menos tan fiable como la actual."""
    prov = record["provenance"]
    top = field.split(".")[0]
    if top != field and top in prov and isinstance(record.get(top), dict):
        # Al tocar un subcampo, la procedencia del padre pasa a cada subcampo.
        parent = prov.pop(top)
        for sub in record[top]:
            prov.setdefault(f"{top}.{sub}", dict(parent))
    current = prov.get(field) or prov.get(top)
    if current and STATUS_RANK[status] < STATUS_RANK[current["status"]]:
        return False
    set_path(record, field, value)
    prov[field] = {"status": status, "source": source}
    return True


def collapse_provenance(prov):
    """Estado por campo principal; si sus subcampos difieren, el menos fiable."""
    out = {}
    for key, value in prov.items():
        top = key.split(".")[0]
        if top not in out or STATUS_RANK[value["status"]] < STATUS_RANK[out[top]]:
            out[top] = value["status"]
    return out


def best_status(record):
    statuses = [p["status"] for p in record["provenance"].values()]
    return max(statuses, key=STATUS_RANK.get) if statuses else "unknown"


# ---------------------------------------------------------------- fuentes

def normalize_boss(boss):
    if isinstance(boss, str):
        return {"name": {"en": boss}}
    out = dict(boss)
    if isinstance(out.get("name"), str):
        out["name"] = {"en": out["name"]}
    return out


def load_seed():
    seed = json.loads((SEED_DIR / "dungeons.json").read_text(encoding="utf-8"))
    status = seed["status"]
    records = {}
    for raw in seed["dungeons"]:
        rec = copy.deepcopy(raw)
        rec["bosses"] = [normalize_boss(b) for b in rec.get("bosses", [])]
        rec["provenance"] = {f: {"status": status, "source": "seed"} for f in TRACKED_FIELDS if f in rec}
        records[rec["id"]] = rec
    return records


def latest_raw(source_id, category):
    stamps = sorted((RAW_DIR / source_id).glob("*")) if (RAW_DIR / source_id).exists() else []
    for stamp in reversed(stamps):
        path = stamp / f"{category}.json"
        if path.exists():
            return path
    return None


def apply_imports(records, notes):
    """Fusiona las descargas de fuentes externas configuradas en sources.json."""
    from probe_sources import extract_records

    sources = json.loads(SOURCES_FILE.read_text(encoding="utf-8"))["sources"]
    by_instance = {r["instanceID"]: r for r in records.values()}
    for source in sources:
        for spec in source.get("imports", []):
            if not source.get("redistribution_allowed"):
                notes.append(f"{source['name']}: importación «{spec['endpoint']}» omitida, falta confirmar redistribution_allowed.")
                continue
            path = latest_raw(source["id"], spec["endpoint"])
            if path is None:
                notes.append(f"{source['name']}: no hay descarga de «{spec['endpoint']}»; ejecuta probe_sources.py.")
                continue
            items = extract_records(json.loads(path.read_text(encoding="utf-8"))) or []
            matched = 0
            for item in items:
                instance_id = get_path(item, spec["fields"]["instanceID"])
                record = by_instance.get(instance_id)
                if record is None:
                    continue
                matched += 1
                for field, src_path in spec["fields"].items():
                    value = get_path(item, src_path)
                    if value is not None and field != "instanceID":
                        apply_field(record, field, value, spec.get("status", "datamined"), source["id"])
            notes.append(f"{source['name']}: {matched} de {len(items)} registros de «{spec['endpoint']}» enlazados por instanceID.")


def load_contributions():
    files = sorted(CONTRIB_DIR.glob("*.json")) if CONTRIB_DIR.exists() else []
    return [(f.name, json.loads(f.read_text(encoding="utf-8"))) for f in files]


def apply_contributions(records, contributions, notes):
    by_instance = {r["instanceID"]: r for r in records.values()}
    quests = {}
    builds = set()
    for name, contrib in contributions:
        source = f"contribution:{name}"
        builds.update(contrib.get("builds", []))
        for key, obs in contrib.get("instances", {}).items():
            instance_id = int(key)
            if obs.get("type") not in ("party", "raid"):
                continue
            record = by_instance.get(instance_id)
            if record is None:
                # Mazmorra que no estaba en ninguna fuente: probablemente contenido nuevo de Forever.
                record = {"id": f"instance_{instance_id}", "instanceID": instance_id, "bosses": [], "provenance": {}}
                apply_field(record, "type", "raid" if obs["type"] == "raid" else "dungeon", "verified_ingame", source)
                if obs.get("maxPlayers"):
                    apply_field(record, "size", obs["maxPlayers"], "verified_ingame", source)
                records[record["id"]] = by_instance[instance_id] = record
                notes.append(f"Nueva instancia observada en el juego: {obs.get('name')} ({instance_id}).")
            if obs.get("name"):
                lang = lang_of(obs.get("locale", "enUS"))
                previous = get_path(record, f"name.{lang}")
                if previous and previous != obs["name"]:
                    notes.append(f"{record['id']}: nombre «{previous}» corregido a «{obs['name']}» según el juego.")
                apply_field(record, f"name.{lang}", obs["name"], "verified_ingame", source)
            observed = record.setdefault("observed", {})
            observed["uiMapIDs"] = sorted(set(observed.get("uiMapIDs", [])) | {int(m) for m in obs.get("uiMapIDs", [])})
            encounters = {e["id"]: e for e in observed.get("encounters", [])}
            for enc_id, enc in obs.get("encounters", {}).items():
                encounters[int(enc_id)] = {"id": int(enc_id), "name": enc.get("name")}
            observed["encounters"] = [encounters[k] for k in sorted(encounters)]
            levels = sorted(int(lv) for lv in obs.get("levels", {}))
            if levels:
                seen = observed.get("levelsSeen", {})
                observed["levelsSeen"] = {"min": min([seen.get("min", levels[0]), levels[0]]),
                                          "max": max([seen.get("max", levels[-1]), levels[-1]])}
            if obs.get("entrance") and not observed.get("entrance"):
                observed["entrance"] = obs["entrance"]
            record["provenance"]["exists"] = {"status": "verified_ingame", "source": source}
        for key, q in contrib.get("quests", {}).items():
            merged = quests.setdefault(int(key), {"id": int(key)})
            for field in ("level", "mapID", "xp"):
                if q.get(field) is not None:
                    merged[field] = q[field]
    return quests, sorted(builds, key=build_key)


# ---------------------------------------------------------------- validación

def validate(records):
    errors = []
    seen_instances = {}
    for rid, r in records.items():
        where = f"{rid}:"
        if r.get("type") not in DUNGEON_TYPES:
            errors.append(f"{where} type inválido {r.get('type')!r}")
        if r.get("faction", "both") not in FACTIONS:
            errors.append(f"{where} faction inválida {r.get('faction')!r}")
        if not isinstance(r.get("instanceID"), int):
            errors.append(f"{where} falta instanceID")
        elif r["instanceID"] in seen_instances:
            errors.append(f"{where} instanceID {r['instanceID']} duplicado con {seen_instances[r['instanceID']]}")
        else:
            seen_instances[r["instanceID"]] = rid
        if not (get_path(r, "name.en") or get_path(r, "name.es")):
            errors.append(f"{where} sin nombre")
        levels = [r.get("levels")] + [w.get("levels") for w in r.get("wings", [])]
        for lv in filter(None, levels):
            if not (1 <= lv.get("min", 0) <= lv.get("max", 0) <= MAX_LEVEL):
                errors.append(f"{where} rango de niveles inválido {lv}")
        wing_ids = {w["id"] for w in r.get("wings", [])}
        for b in r.get("bosses", []):
            if b.get("wing") and b["wing"] not in wing_ids:
                errors.append(f"{where} el jefe {b['name']} apunta al ala inexistente {b['wing']!r}")
        for field, prov in r["provenance"].items():
            if prov["status"] not in STATUS_RANK:
                errors.append(f"{where} estado de verificación desconocido en {field}: {prov['status']}")
    if errors:
        raise ValidationError("\n".join(errors))


# ---------------------------------------------------------------- salida

def diff(old, new, path=""):
    if isinstance(old, dict) and isinstance(new, dict):
        out = []
        for k in sorted(set(old) | set(new), key=str):
            if k == "provenance":
                continue
            out += diff(old.get(k), new.get(k), f"{path}.{k}" if path else str(k))
        return out
    return [] if old == new else [(path, old, new)]


def change_report(old, new, notes):
    added = sorted(set(new) - set(old))
    removed = sorted(set(old) - set(new))
    lines = ["# Cambios en los datos del addon", ""]
    if not (added or removed or any(diff(old[k], new[k]) for k in set(old) & set(new))):
        lines.append("Sin cambios en las mazmorras.")
    for rid in added:
        lines.append(f"- **Nueva:** `{rid}` ({get_path(new[rid], 'name.en') or get_path(new[rid], 'name.es')})")
    for rid in removed:
        lines.append(f"- **Eliminada (revisar):** `{rid}`")
    for rid in sorted(set(old) & set(new)):
        for path, a, b in diff(old[rid], new[rid])[:15]:
            lines.append(f"- `{rid}.{path}`: `{json.dumps(a, ensure_ascii=False)}` → `{json.dumps(b, ensure_ascii=False)}`")
    if notes:
        lines += ["", "## Notas del proceso", ""] + [f"- {n}" for n in notes]
    return "\n".join(lines) + "\n", bool(removed)


def content_hash(payload):
    return hashlib.sha256(json.dumps(payload, sort_keys=True, ensure_ascii=False).encode()).hexdigest()[:10]


def render_outputs(records, quests, builds, previous_meta):
    for r in records.values():
        r["status"] = best_status(r)
    dungeons_by_id = {rid: records[rid] for rid in sorted(records)}
    digest = content_hash({"dungeons": dungeons_by_id, "quests": quests, "builds": builds})

    if previous_meta and previous_meta.get("hash") == digest:
        meta = previous_meta
    else:
        today = dt.date.today()
        meta = {"hash": digest, "version": f"{today:%Y.%m.%d}-{digest[:6]}", "generated": today.isoformat()}
    status_counts = {}
    for r in records.values():
        status_counts[r["status"]] = status_counts.get(r["status"], 0) + 1
    meta.update({
        "counts": {"dungeons": len(records), "questsObserved": len(quests)},
        "statusCounts": status_counts,
        "latestBuildSeen": builds[-1] if builds else None,
    })

    lua_dungeons = {r["instanceID"]: {k: v for k, v in r.items() if k != "provenance"}
                    | {"provenance": collapse_provenance(r["provenance"])} for r in records.values()}
    files = {
        ADDON_DATA_DIR / "Meta.lua": LUA_HEADER + "ns.Data.Meta = " + to_lua(meta) + "\n",
        ADDON_DATA_DIR / "Dungeons.lua": LUA_HEADER + "ns.Data.Dungeons = " + to_lua(lua_dungeons) + "\n",
        SNAPSHOT_DIR / "dungeons.json": json.dumps(dungeons_by_id, indent=2, ensure_ascii=False, sort_keys=True) + "\n",
        SNAPSHOT_DIR / "quests_observed.json": json.dumps({str(k): quests[k] for k in sorted(quests)}, indent=2, ensure_ascii=False) + "\n",
        SNAPSHOT_DIR / "meta.json": json.dumps(meta, indent=2, ensure_ascii=False, sort_keys=True) + "\n",
    }
    return files


def build():
    notes = []
    records = load_seed()
    apply_imports(records, notes)
    quests, builds = apply_contributions(records, load_contributions(), notes)
    validate(records)

    old_path = SNAPSHOT_DIR / "dungeons.json"
    old = json.loads(old_path.read_text(encoding="utf-8")) if old_path.exists() else {}
    meta_path = SNAPSHOT_DIR / "meta.json"
    previous_meta = json.loads(meta_path.read_text(encoding="utf-8")) if meta_path.exists() else None

    files = render_outputs(records, quests, builds, previous_meta)
    new = json.loads(files[SNAPSHOT_DIR / "dungeons.json"])
    report, has_removals = change_report(old, new, notes)
    return files, report, has_removals


def main(argv=None):
    parser = argparse.ArgumentParser(description="Genera los datos del addon.")
    parser.add_argument("--check", action="store_true", help="no escribe; falla si algo generado está desactualizado")
    args = parser.parse_args(argv)

    try:
        files, report, has_removals = build()
    except ValidationError as err:
        sys.exit(f"Validación fallida:\n{err}")

    stale = [p for p, text in files.items() if not p.exists() or p.read_text(encoding="utf-8") != text]
    if args.check:
        if stale:
            sys.exit("Datos generados desactualizados; ejecuta pipeline/build_data.py:\n" + "\n".join(f"  {p.relative_to(ROOT)}" for p in stale))
        print("Datos generados al día.")
        return

    for path in stale:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(files[path], encoding="utf-8", newline="\n")
    REPORT_FILE.parent.mkdir(exist_ok=True)
    REPORT_FILE.write_text(report, encoding="utf-8")
    print(report)
    print(f"{len(stale)} archivo(s) actualizados." + (" Hay eliminaciones: revisión manual obligatoria." if has_removals else ""))
    if os.environ.get("GITHUB_OUTPUT"):
        # Para el flujo de actualización automática (.github/workflows/update-data.yml).
        meta = json.loads(files[SNAPSHOT_DIR / "meta.json"])
        with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as out:
            out.write(f"changed={'true' if stale else 'false'}\nremovals={'true' if has_removals else 'false'}\nversion={meta['version']}\n")


if __name__ == "__main__":
    main()
