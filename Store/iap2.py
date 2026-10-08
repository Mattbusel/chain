"""The 1.2 in-app purchases: Streak Repair and the 99-cent themes and celebration pack.

    python Store/iap2.py create                 make every product (idempotent): text, $0.99, all territories
    python Store/iap2.py shot <kind> <png>      review screenshot for every product of a kind (repair | theme | celebrate)
    python Store/iap2.py status                 show each product's state
    python Store/iap2.py submit                 queue every product for the next version submission
"""
import hashlib
import sys
from pathlib import Path

import requests

sys.path.insert(0, str(Path(__file__).resolve().parent))
import asc  # noqa: E402
import iap  # noqa: E402

THEME_NOTE = ("Non-consumable, one-time. Settings (gear on Today) > Themes, icons and celebrations opens the shop. "
              "Tapping a theme's price buys it; it then recolours the app and widgets and switches the app icon to match. "
              "Restore purchases is in Settings.")
PRODUCTS = [
    # product id suffix, type, name (30 max), description (55 max), kind, review note
    ("repair", "CONSUMABLE", "Streak Repair", "Patch one missed day so your chain carries on.", "repair",
     "Consumable. When a chain of 2+ days breaks, Today shows a 'chain broke' banner (also: Week tab, hold a missed square, "
     "Streak Repair). The sheet offers a free freeze if any are left this month, then Streak Repair for $0.99, which patches "
     "the missed day in gold and keeps the chain. Each purchase repairs one day."),
    ("theme.ember", "NON_CONSUMABLE", "Ember Theme", "An orange theme for the app and widgets, with its icon.", "theme", THEME_NOTE),
    ("theme.tide", "NON_CONSUMABLE", "Tide Theme", "A cyan theme for the app and widgets, with its icon.", "theme", THEME_NOTE),
    ("theme.bloom", "NON_CONSUMABLE", "Bloom Theme", "A pink theme for the app and widgets, with its icon.", "theme", THEME_NOTE),
    ("theme.gold", "NON_CONSUMABLE", "Gold Theme", "A gold theme for the app and widgets, with its icon.", "theme", THEME_NOTE),
    ("theme.violet", "NON_CONSUMABLE", "Violet Theme", "A violet theme for the app and widgets, with its icon.", "theme", THEME_NOTE),
    ("celebrate", "NON_CONSUMABLE", "Celebration Pack", "Fireworks and confetti when you finish the day.", "celebrate",
     "Non-consumable, one-time. Settings > Themes, icons and celebrations > Celebration pack. Adds Fireworks and Confetti "
     "animations that play when the last habit of the day is ticked (Stitch is free). Restore is in Settings."),
]
PRICE = "0.99"
BASE = "com.mattbusel.chainhabits."


def find(pid: str):
    got = asc.call("GET", f"/v1/apps/{iap.app_id()}/inAppPurchasesV2", params={"filter[productId]": pid, "limit": 10})
    for d in (got or {}).get("data", []):
        if d["attributes"]["productId"] == pid:
            return d
    return None


def create():
    terr = None
    for suffix, kind, name, desc, _, note in PRODUCTS:
        pid = BASE + suffix
        it = find(pid)
        if not it:
            made = asc.call("POST", "/v2/inAppPurchases", {"data": {
                "type": "inAppPurchases",
                "attributes": {"name": name, "productId": pid, "inAppPurchaseType": kind, "reviewNote": note, "familySharable": False},
                "relationships": {"app": {"data": {"type": "apps", "id": iap.app_id()}}}}})
            if not made:
                print(f"{pid}: create FAILED"); continue
            it = made["data"]
        iid = it["id"]
        print(f"{pid}: {iid} {it['attributes'].get('state')}")
        locs = asc.call("GET", f"/v2/inAppPurchases/{iid}/inAppPurchaseLocalizations") or {"data": []}
        if not any(l["attributes"]["locale"] == "en-US" for l in locs["data"]):
            r = asc.call("POST", "/v1/inAppPurchaseLocalizations", {"data": {
                "type": "inAppPurchaseLocalizations", "attributes": {"locale": "en-US", "name": name, "description": desc},
                "relationships": {"inAppPurchaseV2": {"data": {"type": "inAppPurchases", "id": iid}}}}})
            print("  localization", "added" if r else "FAILED")
        sched = asc.call("GET", f"/v2/inAppPurchases/{iid}/iapPriceSchedule", quiet=True)
        if not sched or not sched.get("data"):
            points = asc.call("GET", f"/v2/inAppPurchases/{iid}/pricePoints", params={"filter[territory]": "USA", "limit": 200})
            pp = next((d["id"] for d in (points or {}).get("data", []) if d["attributes"].get("customerPrice") == PRICE), None)
            r = pp and asc.call("POST", "/v1/inAppPurchasePriceSchedules", {
                "data": {"type": "inAppPurchasePriceSchedules", "relationships": {
                    "inAppPurchase": {"data": {"type": "inAppPurchases", "id": iid}},
                    "baseTerritory": {"data": {"type": "territories", "id": "USA"}},
                    "manualPrices": {"data": [{"type": "inAppPurchasePrices", "id": "${p1}"}]}}},
                "included": [{"type": "inAppPurchasePrices", "id": "${p1}", "attributes": {"startDate": None},
                              "relationships": {"inAppPurchasePricePoint": {"data": {"type": "inAppPurchasePricePoints", "id": pp}}}}]})
            print("  price", f"${PRICE}" if r else "FAILED")
        avail = asc.call("GET", f"/v2/inAppPurchases/{iid}/inAppPurchaseAvailability", quiet=True)
        if not avail or not avail.get("data"):
            terr = terr or [t["id"] for t in asc.call("GET", "/v1/territories", params={"limit": 200})["data"]]
            r = asc.call("POST", "/v1/inAppPurchaseAvailabilities", {"data": {
                "type": "inAppPurchaseAvailabilities", "attributes": {"availableInNewTerritories": True},
                "relationships": {"inAppPurchase": {"data": {"type": "inAppPurchases", "id": iid}},
                                  "availableTerritories": {"data": [{"type": "territories", "id": t} for t in terr]}}}})
            print("  availability", f"{len(terr)} territories" if r else "FAILED")


def shot(kind: str, png: str):
    data = Path(png).read_bytes()
    for suffix, _, _, _, k, _ in PRODUCTS:
        if k != kind:
            continue
        it = find(BASE + suffix)
        if not it:
            continue
        iid = it["id"]
        cur = asc.call("GET", f"/v2/inAppPurchases/{iid}/appStoreReviewScreenshot", quiet=True)
        if cur and cur.get("data"):
            asc.call("DELETE", f"/v1/inAppPurchaseAppStoreReviewScreenshots/{cur['data']['id']}")
        made = asc.call("POST", "/v1/inAppPurchaseAppStoreReviewScreenshots", {"data": {
            "type": "inAppPurchaseAppStoreReviewScreenshots", "attributes": {"fileName": Path(png).name, "fileSize": len(data)},
            "relationships": {"inAppPurchaseV2": {"data": {"type": "inAppPurchases", "id": iid}}}}})
        if not made:
            print(suffix, "reserve FAILED"); continue
        sid = made["data"]["id"]
        for op in made["data"]["attributes"]["uploadOperations"]:
            headers = {h["name"]: h["value"] for h in op.get("requestHeaders", [])}
            requests.request(op["method"], op["url"], headers=headers, data=data[op["offset"]: op["offset"] + op["length"]], timeout=120).raise_for_status()
        r = asc.call("PATCH", f"/v1/inAppPurchaseAppStoreReviewScreenshots/{sid}", {"data": {
            "type": "inAppPurchaseAppStoreReviewScreenshots", "id": sid,
            "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(data).hexdigest()}}})
        print(suffix, "screenshot", "uploaded" if r else "FAILED")


def status():
    for suffix, *_ in PRODUCTS:
        it = find(BASE + suffix)
        print(f"{BASE + suffix}: {it['id'] + ' ' + it['attributes']['state'] if it else 'missing'}")


def submit():
    for suffix, *_ in PRODUCTS:
        it = find(BASE + suffix)
        if not it:
            continue
        r = asc.call("POST", "/v1/inAppPurchaseSubmissions", {"data": {"type": "inAppPurchaseSubmissions",
                     "relationships": {"inAppPurchaseV2": {"data": {"type": "inAppPurchases", "id": it["id"]}}}}})
        print(suffix, "queued" if r else "refused")


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "status"
    if cmd == "shot":
        shot(sys.argv[2], sys.argv[3])
    else:
        {"create": create, "status": status, "submit": submit}.get(cmd, lambda: sys.exit(__doc__))()
