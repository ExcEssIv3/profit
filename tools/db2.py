"""Download and cache client DB2 tables from wago.tools as CSV."""

import csv
import json
import urllib.request
from pathlib import Path

WAGO = "https://wago.tools"
PRODUCT = "wow_classic_beta"  # WoW Forever beta ships under this product
FOREVER_PREFIX = "1.60."
CACHE_DIR = Path(__file__).parent / ".cache"
USER_AGENT = "profit-addon-tools/0.1"


def _get(url):
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=120) as resp:
        return resp.read()


def latest_build():
    """Return the newest Forever build version listed by wago.tools."""
    builds = json.loads(_get(f"{WAGO}/api/builds"))
    for b in builds.get(PRODUCT, []):
        if b["version"].startswith(FOREVER_PREFIX):
            return b["version"]
    raise RuntimeError(f"no {FOREVER_PREFIX}x build found for {PRODUCT}")


def load(table, build, refresh=False):
    """Return rows of a DB2 table as a list of dicts, downloading it if not cached."""
    path = CACHE_DIR / build / f"{table}.csv"
    if refresh or not path.exists():
        data = _get(f"{WAGO}/db2/{table}/csv?build={build}")
        if data.lstrip().startswith(b"<"):
            raise RuntimeError(f"wago.tools returned HTML for {table} @ {build}; is the build valid?")
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
    with path.open(newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))
