"""Descarga la API pública de Forever Companion y guarda una copia normalizada.

Forever Companion ofrece su API gratis y sin clave, expresamente también para
addons, con la condición de citarlos con un enlace
(https://forevercompanion.io/developers). Sus datos proceden de ForeverChanges,
Wowhead y Zockify, y van comprobados por jugadores.

Resultado: data-sources/imported/forevercompanion.json, que se versiona para
que build_data.py genere siempre lo mismo sin conexión.

La caché del servidor (Netlify) usa solo la ruta como clave e ignora los
parámetros: `/class-quests` puede devolver la variante filtrada que otra
persona pidió antes (`?class=warlock`). Una ruta con más barras (`//zones`) es
otra entrada de caché y devuelve el listado completo, pero sin leer parámetros,
así que no permite paginar. Por eso:
- zonas, misiones de clase, raros y mazmorras: listado completo por esa vía;
- misiones: las de cada mazmorra (vienen completas en su detalle) más la
  primera página del listado (misiones de élite);
- objetos: primera página más los que falten, por ID. La copia versionada se
  reutiliza, así que cada ejecución solo pide los nuevos y renueva un lote.

Uso:
    python pipeline/fetch_forevercompanion.py [--refresh N]
"""

import argparse
import http.client
import json
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT_FILE = ROOT / "data-sources" / "imported" / "forevercompanion.json"
# Progreso de la descarga de objetos (no se versiona): una interrupción no obliga a empezar de cero.
ITEM_CACHE = ROOT / "data-sources" / "raw" / "forevercompanion-items.json"
NETWORK_ERRORS = (urllib.error.URLError, http.client.HTTPException, ConnectionError, TimeoutError)
BASE = "https://forevercompanion.io/api/v1"
USER_AGENT = "ForeverProgressionGuide-pipeline (+https://github.com/ruscuu/Forever-Progression-Guide)"

# Límite publicado: 120 peticiones por minuto. Vamos por debajo.
DELAY = 0.55
ITEM_FIELDS = ("id", "name", "quality", "icon", "itemLevel", "requiredLevel", "slot", "armor",
               "weaponType", "stats", "classicOnly", "verified")


def get(path, retries=4):
    url = path if path.startswith("http") else BASE + path
    for attempt in range(retries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, "Accept": "application/json"})
            with urllib.request.urlopen(req, timeout=60) as resp:
                body = json.loads(resp.read())
            time.sleep(DELAY)
            return body
        except urllib.error.HTTPError as err:
            if err.code == 404:
                return None
            if err.code in (429, 500, 502, 503, 504) and attempt < retries - 1:
                time.sleep(10 * (attempt + 1))
                continue
            raise
        except NETWORK_ERRORS:
            if attempt < retries - 1:
                time.sleep(5 * (attempt + 1))
                continue
            raise
    raise RuntimeError(f"sin respuesta de {url}")


def save_item_cache(items):
    ITEM_CACHE.parent.mkdir(parents=True, exist_ok=True)
    ITEM_CACHE.write_text(json.dumps(list(items.values())), encoding="utf-8")


def referenced_item_ids(dungeons, quests, rares):
    ids = set()
    for d in dungeons:
        ids.update(l["itemId"] for l in d.get("loot") or [] if l.get("itemId"))
    for q in quests:
        ids.update(i["id"] for i in (q.get("rewards") or {}).get("items") or [] if i.get("id"))
    for r in rares:
        ids.update(l["itemId"] for l in r.get("loot") or [] if l.get("itemId"))
    return ids


_slashes = [1]


def get_full(path, expected_min=0):
    """Listado completo por defecto, esquivando la caché que ignora los parámetros.

    Una ruta con barras de más es otra entrada de caché, pero en ella el servidor
    no lee los parámetros: sirve para listados sin paginar, no para paginar.
    """
    for _ in range(6):
        _slashes[0] += 1
        body = get("/" * _slashes[0] + path.lstrip("/"))
        if body and isinstance(body.get("data"), list) and len(body["data"]) >= expected_min:
            return body["data"], body["meta"]
    raise RuntimeError(f"la caché de {path} no devolvió el listado completo")


def summary(item):
    return {k: item.get(k) for k in ITEM_FIELDS}


def fetch(previous, refresh):
    previous = previous or {}

    def at_least(key):
        # Un listado más corto que el anterior suele ser una variante filtrada de la caché.
        return int(len(previous.get(key, [])) * 0.9)

    index = get("")
    listing, meta = get_full("/dungeons", at_least("dungeons"))
    dungeons = [get(f"/dungeons/{d['id']}")["data"] for d in listing]

    # Misiones: el listado completo, más las de cada mazmorra (vienen con todo detalle).
    quests = {}
    for q in get_full("/quests")[0]:
        quests[q.get("questId") or ("name:" + q["name"])] = q
    for d in dungeons:
        for q in d.get("quests") or []:
            quests[q.get("questId") or ("name:" + q["name"])] = q

    zones = get_full("/zones", at_least("zones"))[0]
    class_quests = get_full("/class-quests", at_least("classQuests"))[0]
    rares = get_full("/rares", at_least("rares"))[0]

    items = {i["id"]: summary(i) for i in get_full("/items")[0]}
    old_items = {i["id"]: i for i in previous.get("items", [])}
    if ITEM_CACHE.exists():
        for i in json.loads(ITEM_CACHE.read_text(encoding="utf-8")):
            old_items.setdefault(i["id"], i)
    wanted = referenced_item_ids(dungeons, quests.values(), rares) | set(items)
    missing = sorted(i for i in wanted if i not in items and i not in old_items)
    stale = sorted(i for i in wanted if i not in items and i in old_items)[:refresh]
    failed = []
    for n, item_id in enumerate(missing + stale, 1):
        try:
            body = get(f"/items/{item_id}")
        except NETWORK_ERRORS + (RuntimeError,):
            failed.append(item_id)
            continue
        if body and body.get("data"):
            items[item_id] = summary(body["data"])
        if n % 100 == 0:
            save_item_cache({**old_items, **items})
            print(f"  {n}/{len(missing) + len(stale)} objetos", flush=True)
    if failed:
        print(f"  {len(failed)} objetos no se pudieron descargar; se reintentarán la próxima vez.")
    for item_id in wanted:
        if item_id not in items and item_id in old_items:
            items[item_id] = old_items[item_id]
    print(f"Objetos: {len(items)} ({len(missing)} nuevos pedidos por ID, {len(stale)} renovados).")

    return {
        "source": {
            "name": "Forever Companion",
            "url": "https://forevercompanion.io",
            "api": BASE,
            "attribution": meta.get("attribution"),
            "sources": meta.get("sources"),
            "apiVersion": meta.get("version"),
        },
        "updatedAt": meta.get("updatedAt") or (index.get("meta") or {}).get("updatedAt"),
        "dungeons": sorted(dungeons, key=lambda d: d["id"]),
        "quests": sorted(quests.values(), key=lambda q: (q.get("questId") is None, q.get("questId") or 0, q["name"])),
        "items": [items[k] for k in sorted(items)],
        "zones": sorted(zones, key=lambda z: z["id"]),
        "classQuests": sorted(class_quests, key=lambda c: c["id"]),
        "rares": sorted(rares, key=lambda r: r["id"]),
    }


def without_timestamp(data):
    return {k: v for k, v in data.items() if k != "updatedAt"}


def main(argv=None):
    parser = argparse.ArgumentParser(description="Descarga Forever Companion.")
    parser.add_argument("--refresh", type=int, default=150, help="objetos ya guardados que se vuelven a pedir en cada ejecución")
    args = parser.parse_args(argv)

    previous = json.loads(OUT_FILE.read_text(encoding="utf-8")) if OUT_FILE.exists() else None
    data = fetch(previous, args.refresh)
    if previous and without_timestamp(previous) == without_timestamp(data):
        print("Forever Companion: sin cambios.")
        return
    OUT_FILE.parent.mkdir(parents=True, exist_ok=True)
    OUT_FILE.write_text(json.dumps(data, indent=1, ensure_ascii=False, sort_keys=True) + "\n", encoding="utf-8", newline="\n")
    counts = {k: len(v) for k, v in data.items() if isinstance(v, list)}
    print(f"Forever Companion actualizado ({data['updatedAt']}): {counts}")


if __name__ == "__main__":
    try:
        main()
    except NETWORK_ERRORS + (RuntimeError,) as err:
        # Una fuente caída no rompe la actualización: se conserva la copia anterior.
        print(f"Forever Companion no disponible, se mantiene la copia anterior: {err}", file=sys.stderr)
