"""App Store app preview: turn the CI recording into a 6.9" preview and upload it.

    python Store/preview.py make <recording.mp4> <out.mp4> [start seconds]   trim to 29 s, 886x1920, 30 fps, silent stereo AAC
    python Store/preview.py upload <version> <out.mp4> [locale ...]          replace the 6.9" preview of each locale (default en-US)
    python Store/preview.py status <version>
"""
import hashlib
import subprocess
import sys
import time
from pathlib import Path

import requests

sys.path.insert(0, str(Path(__file__).resolve().parent))
import asc  # noqa: E402

TYPE = "IPHONE_67"


def make(src: str, out: str, start: str = "1.5"):
    cmd = ["ffmpeg", "-y", "-ss", start, "-i", src, "-f", "lavfi", "-i", "anullsrc=channel_layout=stereo:sample_rate=44100",
           "-t", "29", "-vf", "scale=886:1920:force_original_aspect_ratio=decrease,pad=886:1920:(ow-iw)/2:(oh-ih)/2:color=0x0f0f11,fps=30,format=yuv420p",
           "-c:v", "libx264", "-profile:v", "high", "-level", "4.0", "-b:v", "8M", "-maxrate", "10M", "-bufsize", "16M",
           "-c:a", "aac", "-b:a", "256k", "-ar", "44100", "-ac", "2", "-shortest", "-movflags", "+faststart", out]
    subprocess.run(cmd, check=True, capture_output=True)
    print("made", out)


def localization(version: str, locale: str):
    app = asc.find_app()
    v = asc.call("GET", f"/v1/apps/{app['id']}/appStoreVersions", params={"filter[versionString]": version})["data"][0]
    locs = asc.call("GET", f"/v1/appStoreVersions/{v['id']}/appStoreVersionLocalizations", params={"limit": 50})["data"]
    return next((l for l in locs if l["attributes"]["locale"] == locale), None)


def upload(version: str, mp4: str, *locales):
    data = Path(mp4).read_bytes()
    for locale in locales or ("en-US",):
        loc = localization(version, locale)
        if not loc:
            print(locale, "no localization"); continue
        sets = asc.call("GET", f"/v1/appStoreVersionLocalizations/{loc['id']}/appPreviewSets")["data"]
        pset = next((s for s in sets if s["attributes"]["previewType"] == TYPE), None)
        if not pset:
            pset = asc.call("POST", "/v1/appPreviewSets", {"data": {"type": "appPreviewSets", "attributes": {"previewType": TYPE},
                            "relationships": {"appStoreVersionLocalization": {"data": {"type": "appStoreVersionLocalizations", "id": loc["id"]}}}}})["data"]
        for p in asc.call("GET", f"/v1/appPreviewSets/{pset['id']}/appPreviews")["data"]:
            asc.call("DELETE", f"/v1/appPreviews/{p['id']}")
        made = asc.call("POST", "/v1/appPreviews", {"data": {"type": "appPreviews",
                        "attributes": {"fileName": Path(mp4).name, "fileSize": len(data), "mimeType": "video/mp4", "previewFrameTimeCode": "00:00:08:00"},
                        "relationships": {"appPreviewSet": {"data": {"type": "appPreviewSets", "id": pset["id"]}}}}})["data"]
        for op in made["attributes"]["uploadOperations"]:
            h = {x["name"]: x["value"] for x in op.get("requestHeaders", [])}
            requests.request(op["method"], op["url"], headers=h, data=data[op["offset"]: op["offset"] + op["length"]], timeout=300).raise_for_status()
        r = asc.call("PATCH", f"/v1/appPreviews/{made['id']}", {"data": {"type": "appPreviews", "id": made["id"],
                     "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(data).hexdigest()}}})
        print(locale, "preview uploaded" if r else "preview FAILED", made["id"])


def status(version: str):
    loc = localization(version, "en-US")
    for s in asc.call("GET", f"/v1/appStoreVersionLocalizations/{loc['id']}/appPreviewSets")["data"]:
        for p in asc.call("GET", f"/v1/appPreviewSets/{s['id']}/appPreviews")["data"]:
            st = p["attributes"].get("assetDeliveryState") or {}
            print(s["attributes"]["previewType"], p["id"], st.get("state"), st.get("errors"))


if __name__ == "__main__":
    a = sys.argv
    if len(a) < 3:
        sys.exit(__doc__)
    {"make": lambda: make(*a[2:5]), "upload": lambda: upload(a[2], a[3], *a[4:]), "status": lambda: status(a[2])}[a[1]]()
