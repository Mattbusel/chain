"""In-App Events for Chain 1.3, localized from Store/event_copy.json, with card art from Store/art/event_media.mjs.

    python Store/events.py make        create/update both events, localizations and media (idempotent)
    python Store/events.py status
    python Store/events.py submit      add both events to the open review submission draft
"""
import json
import sys
from pathlib import Path

import requests

sys.path.insert(0, str(Path(__file__).resolve().parent))
import asc  # noqa: E402

APP = "6814264554"
HERE = Path(__file__).resolve().parent
MEDIA = HERE / "events"
EVENTS = {
    # key: reference name, badge, deep link, schedule, existing id to reuse
    "update": ("chain 1.3 major update", "MAJOR_UPDATE", "chainhabits://challenge",
               {"publishStart": "2026-10-21T13:00:00Z", "eventStart": "2026-10-22T13:00:00Z", "eventEnd": "2026-11-19T13:00:00Z"}, "6821174979"),
    "challenge": ("chain no-scroll november 2026", "CHALLENGE", "chainhabits://challenge",
                  {"publishStart": "2026-10-25T13:00:00Z", "eventStart": "2026-11-01T04:00:00Z", "eventEnd": "2026-12-01T04:59:00Z"}, None),
}


def upload(lid: str, kind: str, f: Path):
    data = f.read_bytes()
    made = asc.call("POST", "/v1/appEventScreenshots", {"data": {"type": "appEventScreenshots",
                    "attributes": {"fileName": "c13-" + f.name, "fileSize": len(data), "appEventAssetType": kind},
                    "relationships": {"appEventLocalization": {"data": {"type": "appEventLocalizations", "id": lid}}}}})
    if not made:
        print("   reserve FAILED", kind); return
    made = made["data"]
    for op in made["attributes"]["uploadOperations"]:
        h = {x["name"]: x["value"] for x in op.get("requestHeaders", [])}
        requests.request(op["method"], op["url"], headers=h, data=data[op["offset"]: op["offset"] + op["length"]], timeout=120).raise_for_status()
    asc.call("PATCH", f"/v1/appEventScreenshots/{made['id']}", {"data": {"type": "appEventScreenshots", "id": made["id"], "attributes": {"uploaded": True}}})


def find(ref: str, reuse: str | None):
    evs = asc.call("GET", f"/v1/apps/{APP}/appEvents", params={"limit": 50})["data"]
    return next((e for e in evs if e["id"] == reuse or e["attributes"]["referenceName"] == ref), None)


def make():
    copy = json.loads((HERE / "event_copy.json").read_text(encoding="utf-8"))
    terr = [t["id"] for t in asc.call("GET", "/v1/territories", params={"limit": 200})["data"]]
    for key, (ref, badge, link, sched, reuse) in EVENTS.items():
        attrs = {"referenceName": ref, "badge": badge, "deepLink": link, "primaryLocale": "en-US", "priority": "HIGH",
                 "purpose": "APPROPRIATE_FOR_ALL_USERS", "territorySchedules": [dict(territories=terr, **sched)]}
        ev = find(ref, reuse)
        if ev:
            r = asc.call("PATCH", f"/v1/appEvents/{ev['id']}", {"data": {"type": "appEvents", "id": ev["id"], "attributes": attrs}})
            print(key, ev["id"], "updated" if r else "update FAILED")
        else:
            r = asc.call("POST", "/v1/appEvents", {"data": {"type": "appEvents", "attributes": attrs, "relationships": {"app": {"data": {"type": "apps", "id": APP}}}}})
            if not r:
                print(key, "create FAILED"); continue
            ev = r["data"]; print(key, ev["id"], "created")
        locs = {l["attributes"]["locale"]: l for l in asc.call("GET", f"/v1/appEvents/{ev['id']}/localizations", params={"limit": 50})["data"]}
        for loc, c in copy.items():
            name, short, long_ = c[key]
            assert len(name) <= 30 and len(short) <= 50 and len(long_) <= 120 and "—" not in name + short + long_, (loc, key)
            a = {"name": name, "shortDescription": short, "longDescription": long_}
            if loc in locs:
                asc.call("PATCH", f"/v1/appEventLocalizations/{locs[loc]['id']}", {"data": {"type": "appEventLocalizations", "id": locs[loc]["id"], "attributes": a}})
            else:
                r = asc.call("POST", "/v1/appEventLocalizations", {"data": {"type": "appEventLocalizations", "attributes": dict(locale=loc, **a),
                             "relationships": {"appEvent": {"data": {"type": "appEvents", "id": ev["id"]}}}}})
                if not r:
                    print(" ", loc, "localization FAILED"); continue
                locs[loc] = r["data"]
            lid = locs[loc]["id"]
            have = asc.call("GET", f"/v1/appEventLocalizations/{lid}/appEventScreenshots")["data"]
            for s in have:  # media from the old 1.2 draft is replaced
                if not (s["attributes"].get("fileName") or "").startswith("c13-"):
                    asc.call("DELETE", f"/v1/appEventScreenshots/{s['id']}")
            kinds = {s["attributes"]["appEventAssetType"] for s in asc.call("GET", f"/v1/appEventLocalizations/{lid}/appEventScreenshots")["data"]}
            det = MEDIA / key / f"details-{loc}.png"
            if not det.exists():
                det = MEDIA / key / "details-en-US.png"
            for kind, f in (("EVENT_CARD", MEDIA / key / "card.png"), ("EVENT_DETAILS_PAGE", det)):
                if kind not in kinds:
                    upload(lid, kind, f)
            print(" ", loc, "ok")


def status():
    for e in asc.call("GET", f"/v1/apps/{APP}/appEvents", params={"limit": 50})["data"]:
        a = e["attributes"]
        print(e["id"], a["referenceName"], a["eventState"], a.get("badge"), a.get("deepLink"))


def submit():
    subs = asc.call("GET", "/v1/reviewSubmissions", params={"filter[app]": APP, "filter[state]": "READY_FOR_REVIEW", "filter[platform]": "IOS"})["data"]
    if not subs:
        sys.exit("no draft review submission")
    for key, (ref, *_rest) in EVENTS.items():
        ev = find(ref, _rest[-1])
        r = asc.call("POST", "/v1/reviewSubmissionItems", {"data": {"type": "reviewSubmissionItems", "relationships": {
            "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": subs[0]["id"]}},
            "appEvent": {"data": {"type": "appEvents", "id": ev["id"]}}}}})
        print(key, "added" if r else "refused")


if __name__ == "__main__":
    {"make": make, "status": status, "submit": submit}.get(sys.argv[1] if len(sys.argv) > 1 else "status", lambda: sys.exit(__doc__))()
