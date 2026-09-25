"""Chain Unlimited, the one in-app purchase, managed through the App Store Connect API.

    python Store/iap.py create              make it (idempotent): product, en-US text, $4.99, all territories
    python Store/iap.py shot <png>          attach the App Review screenshot of the paywall
    python Store/iap.py free                set the app itself to free
    python Store/iap.py status              show the purchase's state
    python Store/iap.py submit              submit version + purchase for review together
"""
import hashlib
import sys
from pathlib import Path

import requests

sys.path.insert(0, str(Path(__file__).resolve().parent))
import asc  # noqa: E402

PRODUCT_ID = "com.mattbusel.chainhabits.unlimited"
NAME = "Chain Unlimited"
DESCRIPTION = "Unlimited habits, the full year quilt and reminders."  # 55 max
PRICE = "4.99"
REVIEW_NOTE = (
    "Non-consumable, one-time unlock. On a fresh install add three habits, then tap New habit again: "
    "the Chain Unlimited sheet opens with the price, Unlock and Restore purchase. It also opens from the "
    "gear (Settings) on Today, the lock banner on the Year tab, and the Reminder switch in the habit editor. "
    "Buying lifts the three-habit limit, shows the whole year quilt and enables reminders."
)


def app_id() -> str:
    app = asc.find_app()
    if not app:
        sys.exit("no app record")
    return app["id"]


def find_iap():
    got = asc.call("GET", f"/v1/apps/{app_id()}/inAppPurchasesV2", params={"filter[productId]": PRODUCT_ID, "limit": 10})
    for d in (got or {}).get("data", []):
        if d["attributes"]["productId"] == PRODUCT_ID:
            return d
    return None


def create():
    iap = find_iap()
    if iap:
        print(f"exists: {iap['id']} {iap['attributes']['state']}")
    else:
        made = asc.call("POST", "/v2/inAppPurchases", {"data": {
            "type": "inAppPurchases",
            "attributes": {"name": NAME, "productId": PRODUCT_ID, "inAppPurchaseType": "NON_CONSUMABLE",
                           "reviewNote": REVIEW_NOTE, "familySharable": False},
            "relationships": {"app": {"data": {"type": "apps", "id": app_id()}}}}})
        if not made:
            sys.exit("could not create the in-app purchase (Paid Apps Agreement signed?)")
        iap = made["data"]
        print(f"created: {iap['id']}")
    iid = iap["id"]

    locs = asc.call("GET", f"/v2/inAppPurchases/{iid}/inAppPurchaseLocalizations") or {"data": []}
    if not any(l["attributes"]["locale"] == "en-US" for l in locs["data"]):
        r = asc.call("POST", "/v1/inAppPurchaseLocalizations", {"data": {
            "type": "inAppPurchaseLocalizations",
            "attributes": {"locale": "en-US", "name": NAME, "description": DESCRIPTION},
            "relationships": {"inAppPurchaseV2": {"data": {"type": "inAppPurchases", "id": iid}}}}})
        print("  localization", "added" if r else "FAILED")
    else:
        print("  localization ok")

    sched = asc.call("GET", f"/v2/inAppPurchases/{iid}/iapPriceSchedule", quiet=True)
    if not sched or not sched.get("data"):
        points = asc.call("GET", f"/v2/inAppPurchases/{iid}/pricePoints", params={"filter[territory]": "USA", "limit": 200})
        pp = next((d["id"] for d in (points or {}).get("data", []) if d["attributes"].get("customerPrice") == PRICE), None)
        if not pp:
            sys.exit(f"no USA price point at {PRICE}")
        r = asc.call("POST", "/v1/inAppPurchasePriceSchedules", {
            "data": {"type": "inAppPurchasePriceSchedules", "relationships": {
                "inAppPurchase": {"data": {"type": "inAppPurchases", "id": iid}},
                "baseTerritory": {"data": {"type": "territories", "id": "USA"}},
                "manualPrices": {"data": [{"type": "inAppPurchasePrices", "id": "${p1}"}]}}},
            "included": [{"type": "inAppPurchasePrices", "id": "${p1}", "attributes": {"startDate": None},
                          "relationships": {"inAppPurchasePricePoint": {"data": {"type": "inAppPurchasePricePoints", "id": pp}}}}]})
        print("  price", f"${PRICE}" if r else "FAILED")
    else:
        print("  price schedule ok")

    avail = asc.call("GET", f"/v2/inAppPurchases/{iid}/inAppPurchaseAvailability", quiet=True)
    if not avail or not avail.get("data"):
        terr = asc.call("GET", "/v1/territories", params={"limit": 200})
        ids = [t["id"] for t in terr["data"]]
        r = asc.call("POST", "/v1/inAppPurchaseAvailabilities", {"data": {
            "type": "inAppPurchaseAvailabilities", "attributes": {"availableInNewTerritories": True},
            "relationships": {"inAppPurchase": {"data": {"type": "inAppPurchases", "id": iid}},
                              "availableTerritories": {"data": [{"type": "territories", "id": t} for t in ids]}}}})
        print("  availability", f"{len(ids)} territories" if r else "FAILED")
    else:
        print("  availability ok")


def shot(png: str):
    iap = find_iap() or sys.exit("create it first")
    iid = iap["id"]
    cur = asc.call("GET", f"/v2/inAppPurchases/{iid}/appStoreReviewScreenshot", quiet=True)
    if cur and cur.get("data"):
        asc.call("DELETE", f"/v1/inAppPurchaseAppStoreReviewScreenshots/{cur['data']['id']}")
    data = Path(png).read_bytes()
    made = asc.call("POST", "/v1/inAppPurchaseAppStoreReviewScreenshots", {"data": {
        "type": "inAppPurchaseAppStoreReviewScreenshots",
        "attributes": {"fileName": Path(png).name, "fileSize": len(data)},
        "relationships": {"inAppPurchaseV2": {"data": {"type": "inAppPurchases", "id": iid}}}}})
    if not made:
        sys.exit("reserve failed")
    sid = made["data"]["id"]
    for op in made["data"]["attributes"]["uploadOperations"]:
        chunk = data[op["offset"]: op["offset"] + op["length"]]
        headers = {h["name"]: h["value"] for h in op.get("requestHeaders", [])}
        requests.request(op["method"], op["url"], headers=headers, data=chunk, timeout=120).raise_for_status()
    r = asc.call("PATCH", f"/v1/inAppPurchaseAppStoreReviewScreenshots/{sid}", {"data": {
        "type": "inAppPurchaseAppStoreReviewScreenshots", "id": sid,
        "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(data).hexdigest()}}})
    print("review screenshot", "uploaded" if r else "FAILED")


def free():
    aid = app_id()
    points = asc.call("GET", f"/v1/apps/{aid}/appPricePoints", params={"filter[territory]": "USA", "limit": 200})
    pp = next((d["id"] for d in (points or {}).get("data", []) if float(d["attributes"].get("customerPrice") or 1) == 0.0), None)
    if not pp:
        sys.exit("no free price point")
    r = asc.call("POST", "/v1/appPriceSchedules", {
        "data": {"type": "appPriceSchedules", "relationships": {
            "app": {"data": {"type": "apps", "id": aid}},
            "baseTerritory": {"data": {"type": "territories", "id": "USA"}},
            "manualPrices": {"data": [{"type": "appPrices", "id": "${p1}"}]}}},
        "included": [{"type": "appPrices", "id": "${p1}", "attributes": {"startDate": None, "endDate": None},
                      "relationships": {"appPricePoint": {"data": {"type": "appPricePoints", "id": pp}}}}]})
    print("app price:", "Free" if r is not None else "FAILED")


def status():
    iap = find_iap()
    if not iap:
        print("no in-app purchase yet")
        return
    print(f"{iap['attributes']['name']} ({PRODUCT_ID}) id={iap['id']} state={iap['attributes']['state']}")
    sched = asc.call("GET", f"/v1/appPriceSchedules/{app_id()}/manualPrices", params={"include": "appPricePoint", "fields[appPricePoints]": "customerPrice"}, quiet=True)
    for inc in (sched or {}).get("included", []):
        if inc["type"] == "appPricePoints":
            print("app price (base):", inc["attributes"].get("customerPrice"))


def submit(version: str = "1.1"):
    """Put the purchase and the version into one review submission, then submit it."""
    aid = app_id()
    iap = find_iap() or sys.exit("no in-app purchase")
    vers = asc.call("GET", f"/v1/apps/{aid}/appStoreVersions", params={"filter[versionString]": version})
    if not vers or not vers["data"]:
        sys.exit(f"no version {version}")
    vid = vers["data"][0]["id"]
    print("version", version, vers["data"][0]["attributes"]["appStoreState"])
    # The first purchase has to go in with a version: this call queues it for the next version submission.
    r = asc.call("POST", "/v1/inAppPurchaseSubmissions", {"data": {
        "type": "inAppPurchaseSubmissions",
        "relationships": {"inAppPurchaseV2": {"data": {"type": "inAppPurchases", "id": iap["id"]}}}}})
    print("purchase submission:", "queued" if r else "refused (see above)")
    if r is None:
        return
    subs = asc.call("GET", "/v1/reviewSubmissions", params={"filter[app]": aid, "filter[state]": "READY_FOR_REVIEW", "filter[platform]": "IOS"})
    sub = (subs or {}).get("data", [None])[0] if (subs or {}).get("data") else None
    if not sub:
        made = asc.call("POST", "/v1/reviewSubmissions", {"data": {"type": "reviewSubmissions", "attributes": {"platform": "IOS"},
                        "relationships": {"app": {"data": {"type": "apps", "id": aid}}}}})
        sub = made["data"]
    items = asc.call("GET", f"/v1/reviewSubmissions/{sub['id']}/items") or {"data": []}
    if not items["data"]:
        asc.call("POST", "/v1/reviewSubmissionItems", {"data": {"type": "reviewSubmissionItems", "relationships": {
            "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": sub["id"]}},
            "appStoreVersion": {"data": {"type": "appStoreVersions", "id": vid}}}}})
    done = asc.call("PATCH", f"/v1/reviewSubmissions/{sub['id']}", {"data": {"type": "reviewSubmissions", "id": sub["id"], "attributes": {"submitted": True}}})
    print("review submission:", "SUBMITTED" if done else "failed")


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "status"
    {"create": create, "free": free, "status": status, "submit": submit}.get(cmd, lambda: shot(sys.argv[2]) if cmd == "shot" else sys.exit(__doc__))()
