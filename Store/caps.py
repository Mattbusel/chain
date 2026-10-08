"""1.2 capabilities: the widget extension's bundle id, and the capabilities each bundle needs.

    python Store/caps.py            register + enable (idempotent), then print what each bundle has

The app group itself (group.com.mattbusel.chainhabits) cannot be created through the API; it is made once in
the developer portal and assigned to both bundle ids there.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import asc  # noqa: E402

APP = "com.mattbusel.chainhabits"
WIDGETS = "com.mattbusel.chainhabits.widgets"
WANT = {APP: ["APP_GROUPS", "HEALTHKIT", "ICLOUD"], WIDGETS: ["APP_GROUPS"]}


def bundle(identifier: str, name: str):
    got = asc.call("GET", "/v1/bundleIds", params={"limit": 200, "filter[identifier]": identifier})
    for d in (got or {}).get("data", []):
        if d["attributes"]["identifier"] == identifier:
            return d
    made = asc.call("POST", "/v1/bundleIds", {"data": {"type": "bundleIds", "attributes": {
        "identifier": identifier, "name": name, "platform": "IOS"}}})
    print(f"registered {identifier}")
    return made["data"]


def caps(bid: str):
    got = asc.call("GET", f"/v1/bundleIds/{bid}/bundleIdCapabilities")
    return {d["attributes"]["capabilityType"] for d in (got or {}).get("data", [])}


def main():
    for ident, name in [(APP, "Chain"), (WIDGETS, "ChainWidgets")]:
        b = bundle(ident, name)
        have = caps(b["id"])
        for c in WANT[ident]:
            if c in have:
                continue
            body = {"data": {"type": "bundleIdCapabilities", "attributes": {"capabilityType": c},
                             "relationships": {"bundleId": {"data": {"type": "bundleIds", "id": b["id"]}}}}}
            if c == "ICLOUD":
                body["data"]["attributes"]["settings"] = [{"key": "ICLOUD_VERSION", "options": [{"key": "XCODE_6"}]}]
            r = asc.call("POST", "/v1/bundleIdCapabilities", body)
            print(f"  {ident}: enable {c} -> {'ok' if r else 'FAILED'}")
        print(f"{ident} (id={b['id']}): {sorted(caps(b['id']))}")


if __name__ == "__main__":
    main()
