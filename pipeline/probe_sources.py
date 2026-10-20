"""Sondeo de cobertura de las fuentes de datos (fase 01 del plan).

Descarga cada endpoint configurado en data-sources/sources.json, guarda la
respuesta tal cual en data-sources/raw/ y genera un informe de cobertura en
validation/. Solo usa la biblioteca estándar para funcionar en Windows sin
instalar nada.

Uso:
    python pipeline/probe_sources.py            # descarga y analiza
    python pipeline/probe_sources.py --offline  # analiza la última descarga guardada
"""

import argparse
import datetime as dt
import json
import os
import sys
import urllib.error
import urllib.request
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCES_FILE = ROOT / "data-sources" / "sources.json"
RAW_DIR = ROOT / "data-sources" / "raw"
REPORT_DIR = ROOT / "validation"

USER_AGENT = "ForeverProgressionGuide-coverage-probe/0.1"
ID_KEYS = ("id", "entry", "itemId", "questId", "spellId", "dungeonId")
# Campos donde una fuente podría indicar si el dato está verificado en Forever,
# heredado de Classic o solo anunciado.
STATUS_KEYS = ("status", "verified", "verification", "confidence", "source", "origin", "dataSource")
LIST_WRAPPERS = ("data", "results", "items", "records", "entries")


def extract_records(payload):
    """Devuelve la lista de registros de una respuesta JSON, o None si no la reconoce."""
    if isinstance(payload, list):
        return payload
    if isinstance(payload, dict):
        for key in LIST_WRAPPERS:
            if isinstance(payload.get(key), list):
                return payload[key]
    return None


def analyze(payload):
    """Resume un payload: nº de registros, campos, IDs duplicados y estados de verificación."""
    records = extract_records(payload)
    if records is None:
        return {"recognized": False, "top_level_keys": sorted(payload) if isinstance(payload, dict) else []}

    dicts = [r for r in records if isinstance(r, dict)]
    field_counts = Counter(k for r in dicts for k in r)
    id_key = next((k for k in ID_KEYS if field_counts.get(k)), None)

    duplicates = []
    missing_id = 0
    if id_key:
        ids = Counter()
        for r in dicts:
            if r.get(id_key) is None:
                missing_id += 1
            else:
                ids[r[id_key]] += 1
        duplicates = sorted((i for i, n in ids.items() if n > 1), key=str)

    status_values = {}
    for key in STATUS_KEYS:
        if field_counts.get(key):
            values = Counter(json.dumps(r[key], ensure_ascii=False) for r in dicts if key in r)
            status_values[key] = dict(values.most_common(10))

    return {
        "recognized": True,
        "records": len(records),
        "id_key": id_key,
        "missing_id": missing_id,
        "duplicate_ids": duplicates[:20],
        "duplicate_id_count": len(duplicates),
        # Proporción de registros que traen cada campo: revela huecos de datos.
        "field_fill": {k: round(n / len(dicts), 3) for k, n in field_counts.most_common()} if dicts else {},
        "status_values": status_values,
    }


def fetch(url, headers, timeout=30):
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, "Accept": "application/json", **headers})
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return response.status, response.read()
    except urllib.error.HTTPError as err:
        return err.code, err.read()


def auth_headers(source):
    if source.get("auth") != "api_key":
        return {}, None
    key = os.environ.get(source.get("api_key_env") or "")
    if not key:
        return None, f"falta la variable de entorno {source.get('api_key_env')}"
    return {source.get("api_key_header") or "X-API-Key": key}, None


def probe_source(source, stamp, offline):
    result = {"id": source["id"], "name": source["name"], "endpoints": {}}
    endpoints = source.get("endpoints") or {}
    if not endpoints:
        result["error"] = "sin endpoints configurados en sources.json"
        return result

    headers, error = ({}, None) if offline else auth_headers(source)
    if error:
        result["error"] = error
        return result

    out_dir = RAW_DIR / source["id"] / stamp
    for category, path in endpoints.items():
        raw_file = out_dir / f"{category}.json"
        entry = {"path": path}
        try:
            if offline:
                body = raw_file.read_bytes()
                entry["http_status"] = None
            else:
                status, body = fetch(source["base_url"].rstrip("/") + "/" + path.lstrip("/"), headers)
                entry["http_status"] = status
                if status >= 400:
                    entry["error"] = f"HTTP {status}"
                    result["endpoints"][category] = entry
                    continue
                out_dir.mkdir(parents=True, exist_ok=True)
                raw_file.write_bytes(body)
            entry["bytes"] = len(body)
            entry.update(analyze(json.loads(body)))
        except (OSError, urllib.error.URLError) as err:
            entry["error"] = f"{type(err).__name__}: {err}"
        except json.JSONDecodeError as err:
            entry["error"] = f"respuesta no JSON: {err}"
        result["endpoints"][category] = entry
    return result


def render_markdown(results, stamp):
    lines = [f"# Informe de cobertura · {stamp}", ""]
    for src in results:
        lines += [f"## {src['name']}", ""]
        if "error" in src:
            lines += [f"- No sondeada: {src['error']}", ""]
            continue
        lines += ["| Categoría | HTTP | Registros | Campo ID | IDs duplicados | Sin ID | Campos de estado |",
                  "| --- | --- | --- | --- | --- | --- | --- |"]
        for category, e in src["endpoints"].items():
            http = e.get("http_status") or "—"
            if "error" in e:
                lines.append(f"| {category} | {http} | error: {e['error']} | | | | |")
            elif not e["recognized"]:
                lines.append(f"| {category} | {http} | formato no reconocido ({', '.join(e['top_level_keys'][:6])}) | | | | |")
            else:
                status = ", ".join(e["status_values"]) or "ninguno"
                lines.append(f"| {category} | {http} | {e['records']} | {e['id_key'] or '—'} | "
                             f"{e['duplicate_id_count']} | {e['missing_id']} | {status} |")
        lines.append("")
    return "\n".join(lines)


def latest_stamp():
    stamps = sorted({p.name for p in RAW_DIR.glob("*/*") if p.is_dir()})
    return stamps[-1] if stamps else None


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--offline", action="store_true", help="analizar la última descarga sin conectarse")
    args = parser.parse_args(argv)

    stamp = latest_stamp() if args.offline else dt.datetime.now().strftime("%Y%m%d-%H%M%S")
    if stamp is None:
        sys.exit("No hay descargas previas en data-sources/raw/.")

    sources = json.loads(SOURCES_FILE.read_text(encoding="utf-8"))["sources"]
    results = [probe_source(s, stamp, args.offline) for s in sources]

    REPORT_DIR.mkdir(exist_ok=True)
    (REPORT_DIR / f"coverage-{stamp}.json").write_text(json.dumps(results, indent=2, ensure_ascii=False), encoding="utf-8")
    report = render_markdown(results, stamp)
    (REPORT_DIR / f"coverage-{stamp}.md").write_text(report, encoding="utf-8")
    print(report)


if __name__ == "__main__":
    main()
