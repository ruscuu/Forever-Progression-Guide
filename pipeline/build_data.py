"""Genera los datos del addon a partir de todas las fuentes.

Orden de fusión (de menor a mayor prioridad, campo a campo):
  1. data-sources/imported/forevercompanion.json  mazmorras, misiones, objetos,
     zonas, misiones de clase y raros de Forever (pipeline/fetch_forevercompanion.py)
  2. data-sources/seed/                           IDs de instancia, nombres en
     español y bandas (heredados de Classic)
  3. otras fuentes externas importadas             solo si sources.json marca redistribution_allowed
  4. data-sources/contributions/                   observaciones hechas dentro del juego

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
IMPORTED_FC = ROOT / "data-sources" / "imported" / "forevercompanion.json"
ZONE_TRANSLATIONS = ROOT / "data-sources" / "translations" / "zones.json"
CONTRIB_DIR = ROOT / "data-sources" / "contributions"
RAW_DIR = ROOT / "data-sources" / "raw"
SOURCES_FILE = ROOT / "data-sources" / "sources.json"
SNAPSHOT_DIR = ROOT / "data-sources" / "generated"
ADDON_DATA_DIR = ROOT / "ForeverProgressionGuide" / "Data"
REPORT_FILE = ROOT / "validation" / "changes-latest.md"

STATUS_RANK = {"unknown": 0, "announced": 1, "classic_inherited": 2, "datamined": 3, "verified_ingame": 4}
DUNGEON_TYPES = {"dungeon", "raid"}
FACTIONS = {"both", "alliance", "horde"}
MAX_LEVEL = 60  # límite de validación, no de juego: se sube si Forever amplía el nivel máximo
TRACKED_FIELDS = ("name", "zone", "levels", "bosses", "size", "type", "faction", "entrance", "notes", "quests", "loot")
# Forever Companion marca cada misión: beta (vista en Forever), classic (heredada) o announced.
FC_CONFIDENCE = {"beta": "datamined", "classic": "classic_inherited", "announced": "announced"}
VERIFIED_PLAYERS = 3  # mismo umbral que Forever Companion para «verificado en el juego»
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


def normalize_name(name):
    name = (name or "").lower().strip()
    for article in ("the ", "las ", "los ", "la ", "el "):
        if name.startswith(article):
            return name[len(article):]
    return name


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


def normalize_boss(boss):
    if isinstance(boss, str):
        return {"name": {"en": boss}}
    out = dict(boss)
    if isinstance(out.get("name"), str):
        out["name"] = {"en": out["name"]}
    return out


# ---------------------------------------------------------------- Forever Companion

def load_fc():
    if not IMPORTED_FC.exists():
        return None
    return json.loads(IMPORTED_FC.read_text(encoding="utf-8"))


def fc_dungeons(fc, zones_es):
    records = {}
    for d in fc["dungeons"]:
        status = "announced" if d.get("status") == "announced" else "datamined"
        rec = {
            "id": d["id"], "type": "dungeon", "size": 5,
            "name": {"en": d["name"]},
            "zone": {"en": d["zone"], **({"es": zones_es[d["zone"]]} if d["zone"] in zones_es else {})},
            "levels": {"min": d["minLevel"], "max": d["maxLevel"]},
            "faction": d.get("access") or "both",
            "isNew": bool(d.get("isNew")),
            "available": d.get("status") != "announced" and not d.get("betaLocked"),
            "bosses": [{"name": {"en": b}} for b in d.get("bosses") or []],
            "quests": sorted({q["questId"] for q in d.get("quests") or [] if q.get("questId")}),
            "loot": [{"itemId": l["itemId"], **({"source": l["source"]} if l.get("source") else {})}
                     for l in d.get("loot") or [] if l.get("itemId")],
            "url": d.get("url"),
            "provenance": {},
        }
        if d.get("entrance"):
            rec["entrance"] = {"en": d["entrance"]}
        if d.get("notes"):
            rec["notes"] = {"en": list(d["notes"])}
        for field in TRACKED_FIELDS:
            if field in rec:
                rec["provenance"][field] = {"status": status, "source": "forevercompanion"}
        records[rec["id"]] = rec
    return records


def fc_quests(fc):
    quests = {}
    for q in fc["quests"]:
        if not q.get("questId"):
            continue
        status = FC_CONFIDENCE.get(q.get("confidence"), "unknown")
        verified = q.get("verified") or {}
        if verified.get("players", 0) >= VERIFIED_PLAYERS:
            status = "verified_ingame"
        prereqs = [[p["questId"] for p in step if p.get("questId")] for step in q.get("prerequisites") or []]
        quests[q["questId"]] = {k: v for k, v in {
            "id": q["questId"], "type": q.get("type"), "name": {"en": q["name"]},
            "level": q.get("level"), "minLevel": q.get("minLevel"), "faction": q.get("faction") or "both",
            "classes": q.get("classes"), "xp": q.get("xp"), "xpEstimated": q.get("xpEstimated") or None,
            "dungeon": (q.get("dungeon") or {}).get("id"), "zone": q.get("zone"),
            "giver": q.get("giver"), "location": q.get("location"), "objective": q.get("objective"),
            "rewards": [i["id"] for i in (q.get("rewards") or {}).get("items") or [] if i.get("id")] or None,
            "rewardChoice": (q.get("rewards") or {}).get("choice") or None,
            "prereqs": [step for step in prereqs if step] or None,
            "status": status,
        }.items() if v is not None}
    return quests


def fc_items(fc):
    items = {}
    for i in fc["items"]:
        status = "classic_inherited" if i.get("classicOnly") else "datamined"
        if (i.get("verified") or 0) >= VERIFIED_PLAYERS:
            status = "verified_ingame"
        items[i["id"]] = {k: v for k, v in {
            "id": i["id"], "name": i["name"], "quality": i.get("quality"), "icon": i.get("icon"),
            "ilvl": i.get("itemLevel"), "req": i.get("requiredLevel"), "slot": i.get("slot"),
            "armor": i.get("armor"), "weapon": i.get("weaponType"), "stats": i.get("stats") or None,
            "status": status,
        }.items() if v is not None}
    return items


def fc_zones(fc, zones_es):
    return {z["id"]: {k: v for k, v in {
        "id": z["id"], "name": {"en": z["name"], **({"es": zones_es[z["name"]]} if z["name"] in zones_es else {})},
        "levels": {"min": z["minLevel"], "max": z["maxLevel"]}, "faction": z.get("faction") or "both",
        "isNew": bool(z.get("isNew")), "race": z.get("race"),
    }.items() if v is not None} for z in fc["zones"]}


def fc_class_quests(fc):
    return {c["id"]: {k: v for k, v in {
        "id": c["id"], "class": c["class"].upper(), "level": c["level"], "name": c["name"],
        "faction": c.get("faction") or "both", "races": c.get("races"), "giver": c.get("giver"),
        "location": c.get("location"), "reward": c.get("reward"), "essential": bool(c.get("essential")),
    }.items() if v is not None} for c in fc["classQuests"]}


def fc_rares(fc):
    return {r["id"]: {k: v for k, v in {
        "id": r["id"], "name": r["name"], "zone": r["zone"], "levels": r.get("levels"),
        "faction": r.get("faction") or "both", "coords": r.get("coords") or None, "elite": bool(r.get("elite")),
        "loot": [l["itemId"] for l in r.get("loot") or [] if l.get("itemId")] or None,
    }.items() if v is not None} for r in fc["rares"]}


# ---------------------------------------------------------------- semilla

def load_zone_translations():
    if not ZONE_TRANSLATIONS.exists():
        return {}
    return json.loads(ZONE_TRANSLATIONS.read_text(encoding="utf-8"))["zones"]


def load_seed(records=None):
    """Añade a los registros los IDs de instancia y nombres en español, y las bandas."""
    records = records if records is not None else {}
    seed = json.loads((SEED_DIR / "dungeons.json").read_text(encoding="utf-8"))
    status = seed["status"]
    for entry in seed["dungeons"]:
        rec = records.get(entry["id"])
        if rec is None:
            # Sin Forever Companion (p. ej. pruebas): registro mínimo con lo que da la semilla.
            rec = records[entry["id"]] = {"id": entry["id"], "type": "dungeon", "name": {}, "bosses": [], "provenance": {}}
        rec["instanceID"] = entry["instanceID"]
        for lang, name in entry.get("name", {}).items():
            apply_field(rec, f"name.{lang}", name, status, "seed")
    for raw in seed.get("raids", []):
        rec = copy.deepcopy(raw)
        rec["bosses"] = [normalize_boss(b) for b in rec.get("bosses", [])]
        rec["available"] = True
        rec["provenance"] = {f: {"status": status, "source": "seed"} for f in TRACKED_FIELDS if f in rec}
        records[rec["id"]] = rec
    return records


# ---------------------------------------------------------------- otras fuentes

def latest_raw(source_id, category):
    stamps = sorted((RAW_DIR / source_id).glob("*")) if (RAW_DIR / source_id).exists() else []
    for stamp in reversed(stamps):
        path = stamp / f"{category}.json"
        if path.exists():
            return path
    return None


def by_instance(records):
    index = {}
    for r in records.values():
        if r.get("instanceID") is not None:
            index.setdefault(r["instanceID"], []).append(r)
    return index


def apply_imports(records, notes):
    """Fusiona las descargas de fuentes externas configuradas en sources.json."""
    from probe_sources import extract_records

    sources = json.loads(SOURCES_FILE.read_text(encoding="utf-8"))["sources"]
    index = by_instance(records)
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
                targets = index.get(get_path(item, spec["fields"]["instanceID"]), [])
                if targets:
                    matched += 1
                for record in targets:
                    for field, src_path in spec["fields"].items():
                        value = get_path(item, src_path)
                        if value is not None and field != "instanceID":
                            apply_field(record, field, value, spec.get("status", "datamined"), source["id"])
            notes.append(f"{source['name']}: {matched} de {len(items)} registros de «{spec['endpoint']}» enlazados por instanceID.")


def load_contributions():
    files = sorted(CONTRIB_DIR.glob("*.json")) if CONTRIB_DIR.exists() else []
    return [(f.name, json.loads(f.read_text(encoding="utf-8"))) for f in files]


def find_by_name(records, name):
    """Mazmorra aún sin instanceID cuyo nombre (en cualquier idioma) coincide."""
    key = normalize_name(name)
    for r in records.values():
        if r.get("instanceID") is None and any(normalize_name(n) == key for n in (r.get("name") or {}).values()):
            return r
    return None


def apply_contributions(records, contributions, notes):
    quests = {}
    builds = set()
    for file_name, contrib in contributions:
        source = f"contribution:{file_name}"
        builds.update(contrib.get("builds", []))
        for key, obs in contrib.get("instances", {}).items():
            instance_id = int(key)
            if obs.get("type") not in ("party", "raid"):
                continue
            targets = by_instance(records).get(instance_id, [])
            if not targets and obs.get("name"):
                # Mazmorra nueva de Forever que ya teníamos por nombre: aprendemos su instanceID.
                match = find_by_name(records, obs["name"])
                if match:
                    match["instanceID"] = instance_id
                    match["provenance"]["instanceID"] = {"status": "verified_ingame", "source": source}
                    targets = [match]
                    notes.append(f"{match['id']}: instanceID {instance_id} aprendido en el juego.")
            if not targets:
                # Mazmorra que no estaba en ninguna fuente.
                record = {"id": f"instance-{instance_id}", "instanceID": instance_id, "bosses": [], "provenance": {}}
                apply_field(record, "type", "raid" if obs["type"] == "raid" else "dungeon", "verified_ingame", source)
                if obs.get("maxPlayers"):
                    apply_field(record, "size", obs["maxPlayers"], "verified_ingame", source)
                record["available"] = True
                records[record["id"]] = record
                targets = [record]
                notes.append(f"Nueva instancia observada en el juego: {obs.get('name')} ({instance_id}).")
            for record in targets:
                # Varias alas comparten instancia (Monasterio Escarlata): el nombre del juego no distingue el ala.
                if obs.get("name") and len(targets) == 1:
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


def apply_translations(quests, items, contributions, notes):
    """Nombres recogidos en el juego con /wfg traducir, en el idioma de cada cliente."""
    applied = 0
    for _, contrib in contributions:
        for locale, data in (contrib.get("translations") or {}).items():
            lang = lang_of(locale)
            if lang == "en":
                continue  # Forever Companion ya da los nombres en inglés
            for key, name in data.get("quests", {}).items():
                q = quests.get(int(key))
                if q and name:
                    q["name"][lang] = name
                    applied += 1
            for key, name in data.get("items", {}).items():
                item = items.get(int(key))
                if item and name:
                    if isinstance(item["name"], str):
                        item["name"] = {"en": item["name"]}
                    item["name"][lang] = name
                    applied += 1
    if applied:
        notes.append(f"{applied} nombres traducidos aplicados desde el juego.")


# ---------------------------------------------------------------- validación

def validate(records, quests=None, items=None, notes=None):
    errors = []
    for rid, r in records.items():
        where = f"{rid}:"
        if r.get("type") not in DUNGEON_TYPES:
            errors.append(f"{where} type inválido {r.get('type')!r}")
        if r.get("faction", "both") not in FACTIONS:
            errors.append(f"{where} faction inválida {r.get('faction')!r}")
        if r.get("instanceID") is not None and not isinstance(r["instanceID"], int):
            errors.append(f"{where} instanceID no numérico")
        if not (get_path(r, "name.en") or get_path(r, "name.es")):
            errors.append(f"{where} sin nombre")
        lv = r.get("levels")
        if lv and not (1 <= lv.get("min", 0) <= lv.get("max", 0) <= MAX_LEVEL):
            errors.append(f"{where} rango de niveles inválido {lv}")
        for field, prov in r["provenance"].items():
            if prov["status"] not in STATUS_RANK:
                errors.append(f"{where} estado de verificación desconocido en {field}: {prov['status']}")
        if quests is not None:
            unknown = [q for q in r.get("quests", []) if q not in quests]
            if unknown:
                errors.append(f"{where} misiones inexistentes {unknown}")
        if items is not None and notes is not None:
            missing = [l["itemId"] for l in r.get("loot", []) if l["itemId"] not in items]
            if missing:
                notes.append(f"{rid}: {len(missing)} objetos de su botín sin ficha todavía.")
    for qid, q in (quests or {}).items():
        if q.get("dungeon") and q["dungeon"] not in records:
            errors.append(f"misión {qid}: mazmorra inexistente {q['dungeon']}")
        if q.get("status") not in STATUS_RANK:
            errors.append(f"misión {qid}: estado desconocido {q.get('status')}")
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


def change_report(old, new, notes, counts=None, old_counts=None):
    added = sorted(set(new) - set(old))
    removed = sorted(set(old) - set(new))
    lines = ["# Cambios en los datos del addon", ""]
    if counts:
        lines += ["| Datos | Antes | Ahora |", "| --- | --- | --- |"]
        for key in sorted(counts):
            lines.append(f"| {key} | {(old_counts or {}).get(key, 0)} | {counts[key]} |")
        lines.append("")
    if not (added or removed or any(diff(old[k], new[k]) for k in set(old) & set(new))):
        lines.append("Sin cambios en las mazmorras.")
    for rid in added:
        lines.append(f"- **Nueva:** `{rid}` ({get_path(new[rid], 'name.en') or get_path(new[rid], 'name.es')})")
    for rid in removed:
        lines.append(f"- **Eliminada (revisar):** `{rid}`")
    for rid in sorted(set(old) & set(new)):
        for path, a, b in diff(old[rid], new[rid])[:15]:
            lines.append(f"- `{rid}.{path}`: `{json.dumps(a, ensure_ascii=False)[:120]}` → `{json.dumps(b, ensure_ascii=False)[:120]}`")
    if notes:
        lines += ["", "## Notas del proceso", ""] + [f"- {n}" for n in notes]
    return "\n".join(lines) + "\n", bool(removed)


def content_hash(payload):
    return hashlib.sha256(json.dumps(payload, sort_keys=True, ensure_ascii=False).encode()).hexdigest()[:10]


def lua_table_per_line(name, table):
    """Un registro por línea: archivos grandes legibles y diffs pequeños."""
    lines = [LUA_HEADER + f"ns.Data.{name} = {{"]
    for key in sorted(table):
        k = f"[{key}]" if isinstance(key, int) else f'["{key}"]'
        lines.append(f"  {k} = {to_lua(table[key], compact=True)},")
    lines.append("}")
    return "\n".join(lines) + "\n"


def render_outputs(records, quests, observed_quests, builds, previous_meta, extra=None, source=None):
    extra = extra or {}
    for r in records.values():
        r["status"] = best_status(r)
    dungeons_by_id = {rid: records[rid] for rid in sorted(records)}
    counts = {"dungeons": len(records), "quests": len(quests), "questsObserved": len(observed_quests)}
    for name, table in extra.items():
        counts[name[0].lower() + name[1:]] = len(table)
    digest = content_hash({"dungeons": dungeons_by_id, "quests": quests, "observed": observed_quests,
                           "builds": builds, "extra": extra})

    if previous_meta and previous_meta.get("hash") == digest:
        meta = dict(previous_meta)
    else:
        today = dt.date.today()
        meta = {"hash": digest, "version": f"{today:%Y.%m.%d}-{digest[:6]}", "generated": today.isoformat()}
    status_counts = {}
    for r in records.values():
        status_counts[r["status"]] = status_counts.get(r["status"], 0) + 1
    meta.update({
        "counts": counts,
        "statusCounts": status_counts,
        "latestBuildSeen": builds[-1] if builds else None,
        "credits": source,
    })

    lua_dungeons = {rid: {k: v for k, v in r.items() if k != "provenance"}
                    | {"provenance": collapse_provenance(r["provenance"])} for rid, r in records.items()}
    files = {
        ADDON_DATA_DIR / "Meta.lua": LUA_HEADER + "ns.Data.Meta = " + to_lua(meta) + "\n",
        ADDON_DATA_DIR / "Dungeons.lua": lua_table_per_line("Dungeons", lua_dungeons),
        ADDON_DATA_DIR / "Quests.lua": lua_table_per_line("Quests", quests),
        SNAPSHOT_DIR / "dungeons.json": json.dumps(dungeons_by_id, indent=2, ensure_ascii=False, sort_keys=True) + "\n",
        SNAPSHOT_DIR / "quests_observed.json": json.dumps({str(k): observed_quests[k] for k in sorted(observed_quests)}, indent=2, ensure_ascii=False) + "\n",
        SNAPSHOT_DIR / "meta.json": json.dumps(meta, indent=2, ensure_ascii=False, sort_keys=True) + "\n",
    }
    for name, table in extra.items():
        files[ADDON_DATA_DIR / f"{name}.lua"] = lua_table_per_line(name, table)
    return files


def build():
    notes = []
    zones_es = load_zone_translations()
    fc = load_fc()
    extra, quests, source = {}, {}, None
    if fc:
        records = fc_dungeons(fc, zones_es)
        quests = fc_quests(fc)
        extra = {"Items": fc_items(fc), "Zones": fc_zones(fc, zones_es),
                 "ClassQuests": fc_class_quests(fc), "Rares": fc_rares(fc)}
        source = {"name": fc["source"]["name"], "url": fc["source"]["url"],
                  "sources": [s["name"] for s in fc["source"].get("sources") or [] if isinstance(s, dict)],
                  "updatedAt": fc.get("updatedAt")}
    else:
        records = {}
        notes.append("Sin datos de Forever Companion: ejecuta pipeline/fetch_forevercompanion.py.")
    load_seed(records)
    apply_imports(records, notes)
    contributions = load_contributions()
    observed_quests, builds = apply_contributions(records, contributions, notes)
    if fc:
        apply_translations(quests, extra["Items"], contributions, notes)
    validate(records, quests if fc else None, extra.get("Items"), notes)

    old_path = SNAPSHOT_DIR / "dungeons.json"
    old = json.loads(old_path.read_text(encoding="utf-8")) if old_path.exists() else {}
    meta_path = SNAPSHOT_DIR / "meta.json"
    previous_meta = json.loads(meta_path.read_text(encoding="utf-8")) if meta_path.exists() else None

    files = render_outputs(records, quests, observed_quests, builds, previous_meta, extra, source)
    new = json.loads(files[SNAPSHOT_DIR / "dungeons.json"])
    new_meta = json.loads(files[SNAPSHOT_DIR / "meta.json"])
    report, has_removals = change_report(old, new, notes, new_meta["counts"], (previous_meta or {}).get("counts"))
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
