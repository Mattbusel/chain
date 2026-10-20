"""Replace a version's iPhone screenshots with fastlane/screenshots/<locale>/*.png, in name order.

    python Store/shots_replace.py <version> [--check] [--locale ja]   (locale defaults to en-US)

deliver skips the upload whenever the new version already carries screenshots copied from the
last one, so after a dry_run the old set is still live. This deletes every screenshot in the
6.9" set and uploads the local files. --check only compares checksums and changes nothing.
"""
import hashlib
import sys
import time
from pathlib import Path

import requests

sys.path.insert(0, str(Path(__file__).resolve().parent))
import asc  # noqa: E402

DISPLAY = "APP_IPHONE_67"


def main(version: str, check: bool, locale: str = "en-US"):
    app = asc.find_app()
    v = asc.call("GET", f"/v1/apps/{app['id']}/appStoreVersions", params={"filter[versionString]": version})["data"][0]
    loc = next(l for l in asc.call("GET", f"/v1/appStoreVersions/{v['id']}/appStoreVersionLocalizations")["data"]
               if l["attributes"]["locale"] == locale)
    sets = asc.call("GET", f"/v1/appStoreVersionLocalizations/{loc['id']}/appScreenshotSets")["data"]
    sset = next((s for s in sets if s["attributes"]["screenshotDisplayType"] == DISPLAY), None)
    root = Path(__file__).resolve().parent.parent / "fastlane" / "screenshots" / locale
    files = sorted(root.glob("*.png"))
    local = [hashlib.md5(f.read_bytes()).hexdigest() for f in files]
    remote = []
    if sset:
        remote = [s["attributes"].get("sourceFileChecksum") for s in asc.call("GET", f"/v1/appScreenshotSets/{sset['id']}/appScreenshots", params={"limit": 20})["data"]]
    same = remote == local
    print(f"{app['attributes']['name']} {version} {locale} ({v['attributes']['appStoreState']}): {len(remote)} live, {len(local)} local, {'MATCH' if same else 'DIFFERENT'}")
    if check or same:
        return
    if not sset:
        sset = asc.call("POST", "/v1/appScreenshotSets", {"data": {"type": "appScreenshotSets", "attributes": {"screenshotDisplayType": DISPLAY},
                        "relationships": {"appStoreVersionLocalization": {"data": {"type": "appStoreVersionLocalizations", "id": loc["id"]}}}}})["data"]
    for s in asc.call("GET", f"/v1/appScreenshotSets/{sset['id']}/appScreenshots", params={"limit": 20})["data"]:
        asc.call("DELETE", f"/v1/appScreenshots/{s['id']}")
    for f in files:
        data = f.read_bytes()
        made = asc.call("POST", "/v1/appScreenshots", {"data": {"type": "appScreenshots", "attributes": {"fileName": f.name, "fileSize": len(data)},
                        "relationships": {"appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": sset["id"]}}}}})["data"]
        for op in made["attributes"]["uploadOperations"]:
            headers = {h["name"]: h["value"] for h in op.get("requestHeaders", [])}
            requests.request(op["method"], op["url"], headers=headers, data=data[op["offset"]: op["offset"] + op["length"]], timeout=120).raise_for_status()
        asc.call("PATCH", f"/v1/appScreenshots/{made['id']}", {"data": {"type": "appScreenshots", "id": made["id"],
                 "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(data).hexdigest()}}})
        print("  uploaded", f.name)
    time.sleep(5)
    main(version, True, locale)


if __name__ == "__main__":
    a = sys.argv
    main(a[1], "--check" in a, a[a.index("--locale") + 1] if "--locale" in a else "en-US")
