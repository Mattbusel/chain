"""Chain Plus: the auto-renewable subscription group, managed through the App Store Connect API.

    python Store/subs.py create            group + both subscriptions (idempotent): text, prices in every territory,
                                           availability, the yearly 1-week free trial
    python Store/subs.py locales           group + product localizations for every store locale in LOCALES
    python Store/subs.py shot <png>        App Review screenshot (the paywall) on both subscriptions
    python Store/subs.py status            state of the group and each subscription
    python Store/subs.py ownercode         offer code for Unlimited owners (needs the subscriptions approved first)
"""
import hashlib
import sys
from pathlib import Path

import requests

sys.path.insert(0, str(Path(__file__).resolve().parent))
import asc  # noqa: E402

APP = "6814264554"
GROUP_NAME = "Chain Plus"
REVIEW_NOTE = (
    "Auto-renewable subscription, group Chain Plus (monthly and yearly; yearly has a 1-week free trial). "
    "Where to find it: Settings (gear on Today) > See plans, the 'Go unlimited' line under the habits on Today, "
    "Stats > Insights, or Today > the month's challenge card > Library (lock icons). The paywall shows both plans "
    "and the one-time Unlimited unlock, with price, period, trial terms, auto-renew text, Terms of Use (Apple EULA), "
    "Privacy Policy, Restore purchases and Redeem code. Plus includes everything in Unlimited, plus 3 Streak Repairs "
    "added at the start of each subscribed month, 5 freezes a month, every theme and celebration, the challenge library "
    "and Insights. Manage subscription is in Settings once subscribed."
)
SUBS = [
    # product id, reference name, period, USA price, en-US display name (35 max), description (55 max)
    ("com.mattbusel.chainhabits.plus.monthly", "Chain Plus Monthly", "ONE_MONTH", "2.99", "Chain Plus, monthly",
     "Monthly Streak Repairs, challenges, insights, themes."),
    ("com.mattbusel.chainhabits.plus.yearly", "Chain Plus Yearly", "ONE_YEAR", "14.99", "Chain Plus, yearly",
     "Monthly Streak Repairs, challenges, insights, themes."),
]
TRIAL = ("com.mattbusel.chainhabits.plus.yearly", "ONE_WEEK")

# Store locale -> (group name, product name monthly, product name yearly, description)
LOCALES = {
    "en-US": ("Chain Plus", "Chain Plus, monthly", "Chain Plus, yearly", "Monthly Streak Repairs, challenges, insights, themes."),
    "en-GB": ("Chain Plus", "Chain Plus, monthly", "Chain Plus, yearly", "Monthly Streak Repairs, challenges, insights, themes."),
    "en-AU": ("Chain Plus", "Chain Plus, monthly", "Chain Plus, yearly", "Monthly Streak Repairs, challenges, insights, themes."),
    "en-CA": ("Chain Plus", "Chain Plus, monthly", "Chain Plus, yearly", "Monthly Streak Repairs, challenges, insights, themes."),
    "es-MX": ("Chain Plus", "Chain Plus, mensual", "Chain Plus, anual", "Reparaciones mensuales, retos, análisis y temas."),
    "es-ES": ("Chain Plus", "Chain Plus, mensual", "Chain Plus, anual", "Reparaciones mensuales, retos, análisis y temas."),
    "de-DE": ("Chain Plus", "Chain Plus, monatlich", "Chain Plus, jährlich", "Monatliche Reparaturen, Challenges, Analysen, Themes."),
    "fr-FR": ("Chain Plus", "Chain Plus, mensuel", "Chain Plus, annuel", "Réparations mensuelles, défis, analyses et thèmes."),
    "pt-BR": ("Chain Plus", "Chain Plus, mensal", "Chain Plus, anual", "Reparos mensais, desafios, análises e temas."),
    "it": ("Chain Plus", "Chain Plus, mensile", "Chain Plus, annuale", "Riparazioni mensili, sfide, statistiche e temi."),
    "ja": ("Chain Plus", "Chain Plus 月額", "Chain Plus 年額", "毎月のストリーク修復、チャレンジ、分析、テーマ。"),
    "ko": ("Chain Plus", "Chain Plus 월간", "Chain Plus 연간", "매달 연속 기록 복구, 챌린지, 분석, 테마."),
    "zh-Hans": ("Chain Plus", "Chain Plus 包月", "Chain Plus 包年", "每月连续记录修复、挑战、洞察和主题。"),
}


def group():
    got = asc.call("GET", f"/v1/apps/{APP}/subscriptionGroups", params={"limit": 50})
    for g in (got or {}).get("data", []):
        if g["attributes"]["referenceName"] == GROUP_NAME:
            return g
    made = asc.call("POST", "/v1/subscriptionGroups", {"data": {"type": "subscriptionGroups", "attributes": {"referenceName": GROUP_NAME},
                    "relationships": {"app": {"data": {"type": "apps", "id": APP}}}}})
    return made["data"] if made else sys.exit("could not create the group")


def find(pid: str):
    g = group()
    got = asc.call("GET", f"/v1/subscriptionGroups/{g['id']}/subscriptions", params={"limit": 50})
    for s in (got or {}).get("data", []):
        if s["attributes"]["productId"] == pid:
            return s
    return None


def territories():
    return [t["id"] for t in asc.call("GET", "/v1/territories", params={"limit": 200})["data"]]


def set_prices(sid: str, usd: str):
    have = asc.call("GET", f"/v1/subscriptions/{sid}/prices", params={"limit": 200, "include": "territory"}) or {"data": []}
    done = {p["relationships"]["territory"]["data"]["id"] for p in have["data"] if p.get("relationships", {}).get("territory", {}).get("data")}
    if len(done) >= 170:
        print(f"  prices ok ({len(done)} territories)")
        return
    pts = asc.call("GET", f"/v1/subscriptions/{sid}/pricePoints", params={"filter[territory]": "USA", "limit": 200})
    base = next((p for p in pts["data"] if p["attributes"]["customerPrice"] == usd), None)
    if not base:
        sys.exit(f"no USA price point at {usd}")
    eq = []
    url = f"/v1/subscriptionPricePoints/{base['id']}/equalizations"
    params = {"limit": 200, "include": "territory"}
    while url:
        r = asc.call("GET", url, params=params)
        eq += r["data"]
        url = r.get("links", {}).get("next"); params = None
    points = [("USA", base["id"])] + [(p["relationships"]["territory"]["data"]["id"], p["id"]) for p in eq]
    todo = [(t, pid) for t, pid in points if t not in done]
    # One PATCH carrying every missing territory's price, instead of one POST each.
    r = asc.call("PATCH", f"/v1/subscriptions/{sid}", {
        "data": {"type": "subscriptions", "id": sid, "relationships": {"prices": {"data": [{"type": "subscriptionPrices", "id": f"${{p{i}}}"} for i, _ in enumerate(todo)]}}},
        "included": [{"type": "subscriptionPrices", "id": f"${{p{i}}}", "attributes": {"startDate": None, "preserveCurrentPrice": False},
                      "relationships": {"subscriptionPricePoint": {"data": {"type": "subscriptionPricePoints", "id": pid}},
                                        "territory": {"data": {"type": "territories", "id": t}}}} for i, (t, pid) in enumerate(todo)]})
    print(f"  prices: {len(todo)} new" if r is not None else "  prices FAILED", f"({len(done)} already, {len(points)} territories with a point)")


def trial(sid: str):
    have = asc.call("GET", f"/v1/subscriptions/{sid}/introductoryOffers", params={"limit": 200, "include": "territory"}) or {"data": []}
    done = {o["relationships"]["territory"]["data"]["id"] for o in have["data"] if o.get("relationships", {}).get("territory", {}).get("data")}
    todo = [t for t in territories() if t not in done]
    if not todo:
        print(f"  free trial ok ({len(done)} territories)"); return
    r = asc.call("PATCH", f"/v1/subscriptions/{sid}", {
        "data": {"type": "subscriptions", "id": sid, "relationships": {"introductoryOffers": {"data": [{"type": "subscriptionIntroductoryOffers", "id": f"${{o{i}}}"} for i, _ in enumerate(todo)]}}},
        "included": [{"type": "subscriptionIntroductoryOffers", "id": f"${{o{i}}}", "attributes": {"duration": TRIAL[1], "offerMode": "FREE_TRIAL", "numberOfPeriods": 1, "startDate": None, "endDate": None},
                      "relationships": {"territory": {"data": {"type": "territories", "id": t}}}} for i, t in enumerate(todo)]})
    print(f"  free trial: {len(todo)} territories" if r is not None else "  free trial FAILED", f"({len(done)} before)")


def create():
    g = group()
    print("group", g["id"])
    gl = asc.call("GET", f"/v1/subscriptionGroups/{g['id']}/subscriptionGroupLocalizations") or {"data": []}
    if not any(l["attributes"]["locale"] == "en-US" for l in gl["data"]):
        r = asc.call("POST", "/v1/subscriptionGroupLocalizations", {"data": {"type": "subscriptionGroupLocalizations",
                     "attributes": {"locale": "en-US", "name": "Chain Plus", "customAppName": "Chain"},
                     "relationships": {"subscriptionGroup": {"data": {"type": "subscriptionGroups", "id": g["id"]}}}}})
        print("  group localization", "added" if r else "FAILED")
    terr = None
    for pid, ref, period, usd, name, desc in SUBS:
        s = find(pid)
        if not s:
            made = asc.call("POST", "/v1/subscriptions", {"data": {"type": "subscriptions", "attributes": {
                "name": ref, "productId": pid, "subscriptionPeriod": period, "familySharable": False,
                "reviewNote": REVIEW_NOTE, "groupLevel": 1},
                "relationships": {"group": {"data": {"type": "subscriptionGroups", "id": g["id"]}}}}})
            if not made:
                print(pid, "create FAILED"); continue
            s = made["data"]
        sid = s["id"]
        print(pid, sid, s["attributes"].get("state"))
        locs = asc.call("GET", f"/v1/subscriptions/{sid}/subscriptionLocalizations") or {"data": []}
        if not any(l["attributes"]["locale"] == "en-US" for l in locs["data"]):
            r = asc.call("POST", "/v1/subscriptionLocalizations", {"data": {"type": "subscriptionLocalizations",
                         "attributes": {"locale": "en-US", "name": name, "description": desc},
                         "relationships": {"subscription": {"data": {"type": "subscriptions", "id": sid}}}}})
            print("  localization", "added" if r else "FAILED")
        av = asc.call("GET", f"/v1/subscriptions/{sid}/subscriptionAvailability", quiet=True)
        if not av or not av.get("data"):
            terr = terr or territories()
            r = asc.call("POST", "/v1/subscriptionAvailabilities", {"data": {"type": "subscriptionAvailabilities",
                         "attributes": {"availableInNewTerritories": True},
                         "relationships": {"subscription": {"data": {"type": "subscriptions", "id": sid}},
                                           "availableTerritories": {"data": [{"type": "territories", "id": t} for t in terr]}}}})
            print("  availability", f"{len(terr)} territories" if r else "FAILED")
        set_prices(sid, usd)
        if pid == TRIAL[0]:
            trial(sid)


def locales():
    g = group()
    gl = {l["attributes"]["locale"]: l for l in (asc.call("GET", f"/v1/subscriptionGroups/{g['id']}/subscriptionGroupLocalizations") or {"data": []})["data"]}
    for loc, (gname, mname, yname, desc) in LOCALES.items():
        if loc not in gl:
            r = asc.call("POST", "/v1/subscriptionGroupLocalizations", {"data": {"type": "subscriptionGroupLocalizations",
                         "attributes": {"locale": loc, "name": gname, "customAppName": "Chain"},
                         "relationships": {"subscriptionGroup": {"data": {"type": "subscriptionGroups", "id": g["id"]}}}}})
            print(loc, "group", "added" if r else "FAILED")
    for pid, *_ in SUBS:
        s = find(pid)
        if not s:
            continue
        have = {l["attributes"]["locale"] for l in (asc.call("GET", f"/v1/subscriptions/{s['id']}/subscriptionLocalizations") or {"data": []})["data"]}
        for loc, (gname, mname, yname, desc) in LOCALES.items():
            if loc in have:
                continue
            assert len(desc) <= 55, (loc, len(desc))
            r = asc.call("POST", "/v1/subscriptionLocalizations", {"data": {"type": "subscriptionLocalizations",
                         "attributes": {"locale": loc, "name": yname if pid.endswith("yearly") else mname, "description": desc},
                         "relationships": {"subscription": {"data": {"type": "subscriptions", "id": s["id"]}}}}})
            print(loc, pid.rsplit(".", 1)[1], "added" if r else "FAILED")


def shot(png: str):
    data = Path(png).read_bytes()
    for pid, *_ in SUBS:
        s = find(pid)
        if not s:
            continue
        cur = asc.call("GET", f"/v1/subscriptions/{s['id']}/appStoreReviewScreenshot", quiet=True)
        if cur and cur.get("data"):
            asc.call("DELETE", f"/v1/subscriptionAppStoreReviewScreenshots/{cur['data']['id']}")
        made = asc.call("POST", "/v1/subscriptionAppStoreReviewScreenshots", {"data": {"type": "subscriptionAppStoreReviewScreenshots",
                        "attributes": {"fileName": Path(png).name, "fileSize": len(data)},
                        "relationships": {"subscription": {"data": {"type": "subscriptions", "id": s["id"]}}}}})
        if not made:
            print(pid, "reserve FAILED"); continue
        sid = made["data"]["id"]
        for op in made["data"]["attributes"]["uploadOperations"]:
            headers = {h["name"]: h["value"] for h in op.get("requestHeaders", [])}
            requests.request(op["method"], op["url"], headers=headers, data=data[op["offset"]: op["offset"] + op["length"]], timeout=120).raise_for_status()
        r = asc.call("PATCH", f"/v1/subscriptionAppStoreReviewScreenshots/{sid}", {"data": {"type": "subscriptionAppStoreReviewScreenshots", "id": sid,
                     "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(data).hexdigest()}}})
        print(pid, "review screenshot", "uploaded" if r else "FAILED")


def status():
    g = group()
    print("group", g["id"], g["attributes"]["referenceName"])
    for pid, *_ in SUBS:
        s = find(pid)
        print(pid, (s["id"] + " " + s["attributes"]["state"]) if s else "missing")


def ownercode():
    """A custom offer code for people who own Unlimited: first month of Plus free (monthly) / first year at a discount is not used."""
    s = find(SUBS[0][0])
    terr = territories()
    r = asc.call("POST", "/v1/subscriptionOfferCodes", {"data": {"type": "subscriptionOfferCodes", "attributes": {
        "name": "Unlimited owners, first month free", "customerEligibilities": ["NEW", "EXPIRED"], "offerEligibility": "STACK_WITH_INTRO_OFFERS",
        "duration": "ONE_MONTH", "offerMode": "FREE_TRIAL", "numberOfPeriods": 1},
        "relationships": {"subscription": {"data": {"type": "subscriptions", "id": s["id"]}},
                          "prices": {"data": [{"type": "subscriptionOfferCodePrices", "id": f"${{p{i}}}"} for i, _ in enumerate(terr)]}}},
        "included": [{"type": "subscriptionOfferCodePrices", "id": f"${{p{i}}}", "relationships": {"territory": {"data": {"type": "territories", "id": t}}}} for i, t in enumerate(terr)]})
    print(r and r["data"]["id"])


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "status"
    if cmd == "shot":
        shot(sys.argv[2])
    else:
        {"create": create, "locales": locales, "status": status, "ownercode": ownercode}.get(cmd, lambda: sys.exit(__doc__))()
