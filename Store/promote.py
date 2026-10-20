"""Promoted in-app purchases: 1024x1024 images (Store/promo/*.png, from Store/art/promo.mjs) and the product page order.

    python Store/promote.py make      upload images and promote: Plus yearly, Plus monthly, Freeze Pack, Streak Repair
    python Store/promote.py status
"""
import hashlib
import sys
from pathlib import Path

import requests

sys.path.insert(0, str(Path(__file__).resolve().parent))
import asc  # noqa: E402

APP = "6814264554"
PROMO = Path(__file__).resolve().parent / "promo"
ITEMS = [  # kind, id, image
    ("subscriptions", "6824730047", "plus-yearly.png"),
    ("subscriptions", "6824729402", "plus-monthly.png"),
    ("inAppPurchases", "6824734094", "freezes.png"),
    ("inAppPurchases", "6820684553", "repair.png"),
]


def image(kind: str, pid: str, f: Path):
    res, rel, rtype = (("subscriptionImages", "subscription", "subscriptions") if kind == "subscriptions"
                       else ("inAppPurchaseImages", "inAppPurchase", "inAppPurchases"))
    base = "/v1/subscriptions" if kind == "subscriptions" else "/v2/inAppPurchases"
    have = asc.call("GET", f"{base}/{pid}/images", quiet=True) or {"data": []}
    data = f.read_bytes()
    md5 = hashlib.md5(data).hexdigest()
    if any((i["attributes"].get("sourceFileChecksum") == md5) for i in have["data"]):
        print(" image ok"); return
    for i in have["data"]:
        asc.call("DELETE", f"/v1/{res}/{i['id']}")
    made = asc.call("POST", f"/v1/{res}", {"data": {"type": res, "attributes": {"fileName": f.name, "fileSize": len(data)},
                    "relationships": {rel: {"data": {"type": rtype, "id": pid}}}}})
    if not made:
        print(" image reserve FAILED"); return
    m = made["data"]
    for op in m["attributes"]["uploadOperations"]:
        h = {x["name"]: x["value"] for x in op.get("requestHeaders", [])}
        requests.request(op["method"], op["url"], headers=h, data=data[op["offset"]: op["offset"] + op["length"]], timeout=120).raise_for_status()
    r = asc.call("PATCH", f"/v1/{res}/{m['id']}", {"data": {"type": res, "id": m["id"], "attributes": {"uploaded": True, "sourceFileChecksum": md5}}})
    print(" image", "uploaded" if r else "FAILED")


def make():
    have = asc.call("GET", f"/v1/apps/{APP}/promotedPurchases", params={"limit": 50, "include": "subscription,inAppPurchaseV2"}) or {"data": []}
    promoted = {}
    for p in have["data"]:
        r = p["relationships"]
        for k in ("subscription", "inAppPurchaseV2"):
            d = r.get(k, {}).get("data")
            if d:
                promoted[d["id"]] = p["id"]
    order = []
    for kind, pid, img in ITEMS:
        print(kind, pid)
        image(kind, pid, PROMO / img)
        if pid not in promoted:
            rel = {"subscription": {"data": {"type": "subscriptions", "id": pid}}} if kind == "subscriptions" else {"inAppPurchaseV2": {"data": {"type": "inAppPurchases", "id": pid}}}
            rel["app"] = {"data": {"type": "apps", "id": APP}}
            r = asc.call("POST", "/v1/promotedPurchases", {"data": {"type": "promotedPurchases", "attributes": {"visibleForAllUsers": True, "enabled": True}, "relationships": rel}})
            if r:
                promoted[pid] = r["data"]["id"]; print(" promoted", r["data"]["id"])
            else:
                print(" promote FAILED")
        if pid in promoted:
            order.append(promoted[pid])
    r = asc.call("PATCH", f"/v1/apps/{APP}/relationships/promotedPurchases", {"data": [{"type": "promotedPurchases", "id": i} for i in order]})
    print("order", "set" if r is not None else "FAILED")


def status():
    have = asc.call("GET", f"/v1/apps/{APP}/promotedPurchases", params={"limit": 50}) or {"data": []}
    for p in have["data"]:
        print(p["id"], p["attributes"])


if __name__ == "__main__":
    {"make": make, "status": status}.get(sys.argv[1] if len(sys.argv) > 1 else "status", lambda: sys.exit(__doc__))()
