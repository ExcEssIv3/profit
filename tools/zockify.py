"""Where recipes are learned, from Zockify's WoW Forever recipe tables (zockify.com/forever).

The client data says which recipes have a recipe item, but not where that item comes from or
which trainer-taught recipes are real; Zockify lists trainers, drops, vendors and quests, plus
the skill each recipe is learned at. Pages are cached in tools/.cache/zockify/.
"""

import html
import re
import time

import db2

URL = "https://www.zockify.com/forever/professions/{}/recipes/"
CACHE_DIR = db2.CACHE_DIR / "zockify"
# Zockify page -> our profession name. Its Mining URL shows the Cooking page.
PAGES = {
    "alchemy": "Alchemy", "blacksmithing": "Blacksmithing", "cooking": "Cooking",
    "enchanting": "Enchanting", "engineering": "Engineering", "first-aid": "First Aid",
    "leatherworking": "Leatherworking", "tailoring": "Tailoring",
}


def _text(fragment):
    return " ".join(html.unescape(re.sub(r"<[^>]+>", " ", fragment)).split()).replace("( ", "(").replace(" )", ")")


def _page(slug, refresh):
    path = CACHE_DIR / f"{slug}.html"
    if refresh or not path.exists():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(db2._get(URL.format(slug)))
        time.sleep(1)
    return path.read_text(encoding="utf-8")


def parse(page, profession):
    """Rows of one recipe table: {profession, name, learn, yellow, grey, sources, items, where, reagents}.

    sources: Zockify's kinds ("trainer", "with-the-profession", "drop", "vendor", "quest",
    "not-known-yet"); items: names of the recipe items (and quests) linked in the source cell;
    where: the source cell's text lines, e.g. "Drop: Scholomance (Trash)".
    """
    rows = []
    for tr in re.findall(r"<tr data-z-datatable-row(.*?)</tr>", page, re.S):
        attrs = dict(re.findall(r'data-(sort-recipe|filter-source)="([^"]*)"', tr))
        cells = re.findall(r"<td[^>]*>(.*?)</td>", tr, re.S)
        skills = {k: int(v) for k, v in re.findall(r'skill--(\w+)" title="[^"]*">(\d+)<', cells[1])}
        items, where = [], []
        for part in re.split(r"<br\s*/?>", cells[-1]):
            if part.lstrip().startswith('<span class="small'):
                if "not known yet" not in part:
                    where.append(_text(part))
            else:
                items += [html.unescape(n) for n in re.findall(r'z-icon-link__name">(.*?)</span>', part)]
        rows.append({
            "profession": profession,
            "name": html.unescape(attrs["sort-recipe"]),
            # Orange starts at the learn level; some rows give it as "Learnable at" instead.
            "learn": skills.get("learn") or skills.get("orange"),
            "yellow": skills.get("yellow"),
            "grey": skills.get("grey"),
            "sources": attrs.get("filter-source", "").split(),
            "items": items,
            "where": where,
            "reagents": sorted(html.unescape(n) for n in
                               re.findall(r'<li>\d+&times;.*?z-icon-link__name">(.*?)</span>', cells[-2], re.S)),
        })
    return rows


def load(refresh=False):
    rows = []
    for slug, profession in PAGES.items():
        page = _page(slug, refresh)
        if f"{profession} recipes" not in page:
            raise SystemExit(f"zockify: {URL.format(slug)} isn't the {profession} table any more")
        rows += parse(page, profession)
    return rows
