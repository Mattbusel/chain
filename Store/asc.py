"""App Store Connect API client.

Everything that can be done to a listing without a compiled binary: registering
the bundle id, creating the app record, and pushing name, subtitle, description,
keywords, support and privacy URLs. All of it runs from Windows.

The one thing it cannot do is attach a build, because a build is a signed IPA and
that genuinely requires macOS. The CI runner does that half.

Usage:
    python Store/asc.py whoami
    python Store/asc.py register-bundle
    python Store/asc.py create-app
    python Store/asc.py push-metadata
    python Store/asc.py status
"""

import datetime as _dt
import json
import os
import sys
import time
from pathlib import Path

import jwt
import requests

KEY_ID = os.environ.get("ASC_KEY_ID", "7ZMV4Z7XB8")
ISSUER_ID = os.environ.get("ASC_ISSUER_ID", "5673d5a6-4fcb-46aa-8f10-7e1af68f8143")
KEY_PATH = Path(
    os.environ.get(
        "ASC_KEY_PATH",
        str(Path.home() / "Downloads" / f"AuthKey_{KEY_ID}.p8"),
    )
)

BUNDLE_ID = "com.mattbusel.chainhabits"
APP_NAME = "Chain"
SKU = "chain-1"
PRIMARY_LOCALE = "en-US"

BASE = "https://api.appstoreconnect.apple.com"
META = Path(__file__).resolve().parent.parent / "fastlane" / "metadata" / PRIMARY_LOCALE


def token() -> str:
    """A fresh twenty minute ES256 token.

    Apple rejects anything longer lived than that, so this is minted per run
    rather than cached anywhere.
    """
    if not KEY_PATH.exists():
        sys.exit(f"private key not found at {KEY_PATH}")
    private_key = KEY_PATH.read_text()
    now = int(time.time())
    payload = {
        "iss": ISSUER_ID,
        "iat": now - 60,
        "exp": now + 20 * 60,
        "aud": "appstoreconnect-v1",
    }
    return jwt.encode(
        payload, private_key, algorithm="ES256", headers={"kid": KEY_ID, "typ": "JWT"}
    )


def call(method: str, path: str, body=None, params=None, quiet=False):
    url = path if path.startswith("http") else BASE + path
    headers = {
        "Authorization": f"Bearer {token()}",
        "Content-Type": "application/json",
    }
    for attempt in range(4):
        response = requests.request(
            method, url, headers=headers, json=body, params=params, timeout=60
        )
        if response.status_code != 401:
            break
        # Sporadic 401s from Apple on valid tokens; a fresh token a moment later works.
        time.sleep(2 + attempt * 2)
        headers["Authorization"] = f"Bearer {token()}"
    if response.status_code >= 400:
        if not quiet:
            print(f"  ! {method} {path} -> {response.status_code}")
            try:
                for err in response.json().get("errors", []):
                    print(f"    {err.get('title')}: {err.get('detail')}")
            except Exception:
                print("    " + response.text[:500])
        return None
    if not response.content:
        return {}
    return response.json()


def read_meta(name: str, default: str = "") -> str:
    path = META / name
    if not path.exists():
        return default
    return path.read_text(encoding="utf-8").strip()


# ---------------------------------------------------------------- commands


def whoami():
    """Prove the key works and show what it can see."""
    apps = call("GET", "/v1/apps", params={"limit": 200})
    if apps is None:
        sys.exit("authentication failed")
    print(f"authenticated. {len(apps['data'])} app(s) on this account:")
    for app in apps["data"]:
        a = app["attributes"]
        print(f"  {a.get('name')!r}  {a.get('bundleId')}  id={app['id']}")
    return apps


def find_app():
    apps = call("GET", "/v1/apps", params={"limit": 200, "filter[bundleId]": BUNDLE_ID})
    if apps and apps.get("data"):
        return apps["data"][0]
    return None


def register_bundle():
    """Register the bundle id, if it is not already there."""
    existing = call(
        "GET", "/v1/bundleIds", params={"limit": 200, "filter[identifier]": BUNDLE_ID}
    )
    if existing and existing.get("data"):
        found = existing["data"][0]
        print(f"bundle id already registered: {BUNDLE_ID} (id={found['id']})")
        return found

    made = call(
        "POST",
        "/v1/bundleIds",
        {
            "data": {
                "type": "bundleIds",
                "attributes": {
                    "identifier": BUNDLE_ID,
                    "name": APP_NAME.replace(" ", ""),
                    "platform": "IOS",
                },
            }
        },
    )
    if made:
        print(f"registered bundle id {BUNDLE_ID} (id={made['data']['id']})")
        return made["data"]
    return None


def create_app():
    """Create the app record."""
    existing = find_app()
    if existing:
        print(f"app record already exists: id={existing['id']}")
        return existing

    bundle = register_bundle()
    if not bundle:
        sys.exit("cannot create an app without a registered bundle id")

    made = call(
        "POST",
        "/v1/apps",
        {
            "data": {
                "type": "apps",
                "attributes": {
                    "bundleId": BUNDLE_ID,
                    "name": APP_NAME,
                    "primaryLocale": PRIMARY_LOCALE,
                    "sku": SKU,
                },
                "relationships": {
                    "bundleId": {"data": {"type": "bundleIds", "id": bundle["id"]}}
                },
            }
        },
    )
    if made:
        print(f"created app {APP_NAME!r} id={made['data']['id']}")
        return made["data"]
    return None


def ensure_version(app_id: str, version="1.0"):
    """Find or create the 1.0 version, which the listing text hangs off."""
    versions = call(
        "GET",
        f"/v1/apps/{app_id}/appStoreVersions",
        params={"limit": 10, "filter[platform]": "IOS"},
    )
    if versions:
        for v in versions["data"]:
            if v["attributes"].get("versionString") == version:
                return v
    made = call(
        "POST",
        "/v1/appStoreVersions",
        {
            "data": {
                "type": "appStoreVersions",
                "attributes": {"platform": "IOS", "versionString": version},
                "relationships": {"app": {"data": {"type": "apps", "id": app_id}}},
            }
        },
    )
    return made["data"] if made else None


def push_metadata():
    """Push everything in fastlane/metadata that does not need a binary."""
    app = find_app()
    if not app:
        sys.exit("no app record yet, run create-app first")
    app_id = app["id"]

    # Name and subtitle live on the app info, not on the version.
    infos = call("GET", f"/v1/apps/{app_id}/appInfos", params={"limit": 10})
    if infos and infos.get("data"):
        info_id = infos["data"][0]["id"]
        locs = call(
            "GET",
            f"/v1/appInfos/{info_id}/appInfoLocalizations",
            params={"limit": 50},
        )
        target = None
        for loc in (locs or {}).get("data", []):
            if loc["attributes"].get("locale") == PRIMARY_LOCALE:
                target = loc
                break
        payload = {
            "name": read_meta("name.txt", APP_NAME),
            "subtitle": read_meta("subtitle.txt"),
            "privacyPolicyUrl": read_meta("privacy_url.txt"),
        }
        payload = {k: v for k, v in payload.items() if v}
        if target:
            call(
                "PATCH",
                f"/v1/appInfoLocalizations/{target['id']}",
                {
                    "data": {
                        "type": "appInfoLocalizations",
                        "id": target["id"],
                        "attributes": payload,
                    }
                },
            )
            print(f"  name/subtitle/privacy URL updated")
        else:
            call(
                "POST",
                "/v1/appInfoLocalizations",
                {
                    "data": {
                        "type": "appInfoLocalizations",
                        "attributes": {"locale": PRIMARY_LOCALE, **payload},
                        "relationships": {
                            "appInfo": {"data": {"type": "appInfos", "id": info_id}}
                        },
                    }
                },
            )
            print(f"  name/subtitle/privacy URL created")

    # Description, keywords, promo text and support URL live on the version.
    version = ensure_version(app_id)
    if not version:
        sys.exit("could not find or create the 1.0 version")

    locs = call(
        "GET",
        f"/v1/appStoreVersions/{version['id']}/appStoreVersionLocalizations",
        params={"limit": 50},
    )
    target = None
    for loc in (locs or {}).get("data", []):
        if loc["attributes"].get("locale") == PRIMARY_LOCALE:
            target = loc
            break

    payload = {
        "description": read_meta("description.txt"),
        "keywords": read_meta("keywords.txt"),
        "promotionalText": read_meta("promotional_text.txt"),
        "supportUrl": read_meta("support_url.txt"),
        # whatsNew is deliberately absent. Apple rejects it on a first version
        # with 409 "Attribute 'whatsNew' cannot be edited at this time": release
        # notes only become editable once there is a version to have notes
        # about. Add it back for 1.1.
    }
    payload = {k: v for k, v in payload.items() if v}

    if target:
        call(
            "PATCH",
            f"/v1/appStoreVersionLocalizations/{target['id']}",
            {
                "data": {
                    "type": "appStoreVersionLocalizations",
                    "id": target["id"],
                    "attributes": payload,
                }
            },
        )
        print("  description/keywords/promo/support URL updated")
    else:
        call(
            "POST",
            "/v1/appStoreVersionLocalizations",
            {
                "data": {
                    "type": "appStoreVersionLocalizations",
                    "attributes": {"locale": PRIMARY_LOCALE, **payload},
                    "relationships": {
                        "appStoreVersion": {
                            "data": {"type": "appStoreVersions", "id": version["id"]}
                        }
                    },
                }
            },
        )
        print("  description/keywords/promo/support URL created")


def status():
    app = find_app()
    if not app:
        print("no app record for", BUNDLE_ID)
        return
    print(f"{app['attributes']['name']}  ({BUNDLE_ID})  id={app['id']}")
    versions = call(
        "GET", f"/v1/apps/{app['id']}/appStoreVersions", params={"limit": 5}
    )
    for v in (versions or {}).get("data", []):
        a = v["attributes"]
        print(f"  version {a.get('versionString')}: {a.get('appStoreState')}")
    builds = call("GET", f"/v1/apps/{app['id']}/builds", params={"limit": 5})
    data = (builds or {}).get("data", [])
    print(f"  builds uploaded: {len(data)}")
    for b in data:
        print(f"    {b['attributes'].get('version')} {b['attributes'].get('processingState')}")


COMMANDS = {
    "whoami": whoami,
    "register-bundle": register_bundle,
    "create-app": create_app,
    "push-metadata": push_metadata,
    "status": status,
}

if __name__ == "__main__":
    if len(sys.argv) < 2 or sys.argv[1] not in COMMANDS:
        sys.exit(f"usage: python Store/asc.py [{'|'.join(COMMANDS)}]")
    COMMANDS[sys.argv[1]]()
