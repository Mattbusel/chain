"""Custom Product Pages: one page per audience, each with its own screenshots and promotional text.

    python Store/cpp.py make          create the pages (idempotent by name) and upload each page's screenshots
    python Store/cpp.py status        list pages, versions, states and URLs
    python Store/cpp.py submit        add every page version to the open review submission draft

Screenshots come from Store/art/frame.mjs with an out dir and a shot order, into Store/cpp/<key>/.
"""
import hashlib
import sys
from pathlib import Path

import requests

sys.path.insert(0, str(Path(__file__).resolve().parent))
import asc  # noqa: E402

APP = "6814264554"
ROOT = Path(__file__).resolve().parent / "cpp"
PAGES = {
    "quit": ("Quit habits", "Count the days clean. Log a slip if it happens, keep your best on record, and watch every clean day stitch into a year quilt.",
             ["quit", "today", "rescue", "year", "detail", "insights"]),
    "widgets": ("Home Screen widgets", "Tick habits off right from your Home Screen, Lock Screen or Control Center. Chain is built to take five seconds a day.",
                ["widgets", "today", "themes", "year", "challenges", "rescue"]),
    "challenges": ("30-day challenges", "One habit, one month: a new challenge every month, milestone moments at 7, 30 and 100 days, and Insights on what makes habits stick.",
                   ["challenges", "milestone", "insights", "today", "year", "widgets"]),
}


def pages():
    return {p["attributes"]["name"]: p for p in (asc.call("GET", f"/v1/apps/{APP}/appCustomProductPages", params={"limit": 50}) or {"data": []})["data"]}


def upload_set(loc_id: str, files):
    sets = asc.call("GET", f"/v1/appCustomProductPageLocalizations/{loc_id}/appScreenshotSets")["data"]
    sset = next((s for s in sets if s["attributes"]["screenshotDisplayType"] == "APP_IPHONE_67"), None)
    if not sset:
        sset = asc.call("POST", "/v1/appScreenshotSets", {"data": {"type": "appScreenshotSets", "attributes": {"screenshotDisplayType": "APP_IPHONE_67"},
                        "relationships": {"appCustomProductPageLocalization": {"data": {"type": "appCustomProductPageLocalizations", "id": loc_id}}}}})["data"]
    live = [s["attributes"].get("sourceFileChecksum") for s in asc.call("GET", f"/v1/appScreenshotSets/{sset['id']}/appScreenshots")["data"]]
    local = [hashlib.md5(f.read_bytes()).hexdigest() for f in files]
    if live == local:
        print("  screenshots MATCH"); return
    for s in asc.call("GET", f"/v1/appScreenshotSets/{sset['id']}/appScreenshots")["data"]:
        asc.call("DELETE", f"/v1/appScreenshots/{s['id']}")
    for f in files:
        data = f.read_bytes()
        made = asc.call("POST", "/v1/appScreenshots", {"data": {"type": "appScreenshots", "attributes": {"fileName": f.name, "fileSize": len(data)},
                        "relationships": {"appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": sset["id"]}}}}})["data"]
        for op in made["attributes"]["uploadOperations"]:
            h = {x["name"]: x["value"] for x in op.get("requestHeaders", [])}
            requests.request(op["method"], op["url"], headers=h, data=data[op["offset"]: op["offset"] + op["length"]], timeout=120).raise_for_status()
        asc.call("PATCH", f"/v1/appScreenshots/{made['id']}", {"data": {"type": "appScreenshots", "id": made["id"],
                 "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(data).hexdigest()}}})
    print("  uploaded", len(files), "screenshots")


def make():
    have = pages()
    for key, (name, promo, _) in PAGES.items():
        assert len(promo) <= 170, (key, len(promo))
        p = have.get(name)
        if not p:
            r = asc.call("POST", "/v1/appCustomProductPages", {
                "data": {"type": "appCustomProductPages", "attributes": {"name": name},
                         "relationships": {"app": {"data": {"type": "apps", "id": APP}},
                                           "appCustomProductPageVersions": {"data": [{"type": "appCustomProductPageVersions", "id": "${v1}"}]}}},
                "included": [
                    {"type": "appCustomProductPageVersions", "id": "${v1}",
                     "relationships": {"appCustomProductPageLocalizations": {"data": [{"type": "appCustomProductPageLocalizations", "id": "${l1}"}]}}},
                    {"type": "appCustomProductPageLocalizations", "id": "${l1}", "attributes": {"locale": "en-US", "promotionalText": promo}}]})
            if not r:
                print(key, "create FAILED"); continue
            p = r["data"]
        print(key, p["id"], p["attributes"].get("url"))
        vers = asc.call("GET", f"/v1/appCustomProductPages/{p['id']}/appCustomProductPageVersions")["data"]
        v = vers[-1]
        locs = asc.call("GET", f"/v1/appCustomProductPageVersions/{v['id']}/appCustomProductPageLocalizations")["data"]
        loc = next(l for l in locs if l["attributes"]["locale"] == "en-US")
        if loc["attributes"].get("promotionalText") != promo:
            asc.call("PATCH", f"/v1/appCustomProductPageLocalizations/{loc['id']}", {"data": {"type": "appCustomProductPageLocalizations", "id": loc["id"], "attributes": {"promotionalText": promo}}})
        files = sorted((ROOT / key).glob("*.png"))
        if files:
            upload_set(loc["id"], files)
        else:
            print("  no screenshots in", ROOT / key)


def status():
    for name, p in pages().items():
        vers = asc.call("GET", f"/v1/appCustomProductPages/{p['id']}/appCustomProductPageVersions")["data"]
        print(name, p["id"], p["attributes"].get("url"), [(v["id"], v["attributes"].get("state")) for v in vers])


def submit():
    subs = asc.call("GET", "/v1/reviewSubmissions", params={"filter[app]": APP, "filter[state]": "READY_FOR_REVIEW", "filter[platform]": "IOS"})["data"]
    if not subs:
        sys.exit("no draft review submission")
    for name, p in pages().items():
        v = asc.call("GET", f"/v1/appCustomProductPages/{p['id']}/appCustomProductPageVersions")["data"][-1]
        r = asc.call("POST", "/v1/reviewSubmissionItems", {"data": {"type": "reviewSubmissionItems", "relationships": {
            "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": subs[0]["id"]}},
            "appCustomProductPageVersion": {"data": {"type": "appCustomProductPageVersions", "id": v["id"]}}}}})
        print(name, "added" if r else "refused")


if __name__ == "__main__":
    {"make": make, "status": status, "submit": submit}.get(sys.argv[1] if len(sys.argv) > 1 else "status", lambda: sys.exit(__doc__))()
