"""The rest of the listing: age rating, review details, screenshots.

Split from asc.py only because it is a second chunk of commands, not a second
concern. Everything here needs the app record to already exist, which is the one
step Apple's API refuses to do (`POST /v1/apps` returns 403 by design, so an app
record has to be created once in the web UI).

Usage:
    python Store/listing.py age-rating
    python Store/listing.py review-details
    python Store/listing.py screenshots
    python Store/listing.py finish        # everything that needs no binary
"""

import hashlib
import os
import sys
from pathlib import Path

import requests

sys.path.insert(0, str(Path(__file__).resolve().parent))
from asc import (  # noqa: E402
    PRIMARY_LOCALE,
    call,
    ensure_version,
    find_app,
    push_metadata,
    status,
)


def age_rating():
    """Declare the age rating. Every category is none, which is what 4+ means."""
    app = find_app()
    if not app:
        sys.exit("no app record yet")

    infos = call("GET", f"/v1/apps/{app['id']}/appInfos", params={"limit": 10})
    if not infos or not infos.get("data"):
        print("  no app info found")
        return
    info_id = infos["data"][0]["id"]

    detail = call(
        "GET", f"/v1/appInfos/{info_id}", params={"include": "ageRatingDeclaration"}
    )
    declaration = None
    for included in (detail or {}).get("included", []):
        if included["type"] == "ageRatingDeclarations":
            declaration = included
    if not declaration:
        print("  no age rating declaration attached to this app info")
        return

    # No objectionable content of any kind. All of this is simply
    # true, which is why the rating comes out 4+.
    #
    # The two lists matter: Apple types some of these as frequency enums and
    # some as booleans, and sending the wrong shape fails with a message about a
    # missing attribute rather than a wrong one. Apple also added eight fields
    # in 2026 (messaging, health, parental controls, age assurance, advertising,
    # user generated content, loot box, weapons) and rejects a payload that
    # omits any of them, so the full set is always sent.
    frequency = [
        "violenceCartoonOrFantasy",
        "violenceRealistic",
        "violenceRealisticProlongedGraphicOrSadistic",
        "profanityOrCrudeHumor",
        "matureOrSuggestiveThemes",
        "horrorOrFearThemes",
        "medicalOrTreatmentInformation",
        "alcoholTobaccoOrDrugUseOrReferences",
        "gamblingSimulated",
        "sexualContentOrNudity",
        "sexualContentGraphicAndNudity",
        "contests",
        "gunsOrOtherWeapons",
    ]
    flags = [
        "unrestrictedWebAccess",
        "gambling",
        "lootBox",
        "userGeneratedContent",
        "messagingAndChat",
        "parentalControls",
        "healthOrWellnessTopics",
        "ageAssurance",
        "advertising",
    ]
    attributes = {k: "NONE" for k in frequency}
    attributes.update({k: False for k in flags})

    result = call(
        "PATCH",
        f"/v1/ageRatingDeclarations/{declaration['id']}",
        {
            "data": {
                "type": "ageRatingDeclarations",
                "id": declaration["id"],
                "attributes": attributes,
            }
        },
    )
    print("  age rating declared (4+)" if result is not None else "  age rating failed")


def _review_notes() -> str:
    path = Path(__file__).resolve().parent / "review-notes.md"
    if not path.exists():
        return "No account or login is required. Tap PLAY to start."
    text = path.read_text(encoding="utf-8")
    # Everything after the --- divider is the note itself; the header above it
    # is for whoever opens the file.
    lines = text.splitlines()
    for i, line in enumerate(lines):
        if line.strip() == "---":
            text = os.linesep.join(lines[i + 1:])
            break
    return text.strip()


def review_details():
    """Reviewer contact details, and a note saying how to drive the app."""
    app = find_app()
    if not app:
        sys.exit("no app record yet")
    version = ensure_version(app["id"])
    if not version:
        print("  could not resolve version 1.0")
        return

    attributes = {
        "contactFirstName": "Matthew",
        "contactLastName": "Busel",
        "contactEmail": "mattbusel@gmail.com",
        # No account, so nothing to sign in with. Saying so outright saves a
        # round trip with a reviewer asking for test credentials.
        "demoAccountRequired": False,
        # Read from Store/review-notes.md rather than duplicated here, so the
        # file a human reads and the text Apple receives cannot drift apart.
        # This is the most important field on this particular submission: it is
        # where the satire is explained.
        "notes": _review_notes(),
    }
    phone = os.environ.get("ASC_CONTACT_PHONE", "").strip()
    if phone:
        attributes["contactPhone"] = phone

    existing = call(
        "GET",
        f"/v1/appStoreVersions/{version['id']}/appStoreReviewDetail",
        quiet=True,
    )
    if existing and existing.get("data"):
        detail_id = existing["data"]["id"]
        result = call(
            "PATCH",
            f"/v1/appStoreReviewDetails/{detail_id}",
            {
                "data": {
                    "type": "appStoreReviewDetails",
                    "id": detail_id,
                    "attributes": attributes,
                }
            },
        )
    else:
        result = call(
            "POST",
            "/v1/appStoreReviewDetails",
            {
                "data": {
                    "type": "appStoreReviewDetails",
                    "attributes": attributes,
                    "relationships": {
                        "appStoreVersion": {
                            "data": {"type": "appStoreVersions", "id": version["id"]}
                        }
                    },
                }
            },
        )
    print("  review details set" if result is not None else "  review details failed")


# Apple's display type for each accepted screenshot size, both orientations.
PRICE = "2.99"

DISPLAY_BY_SIZE = {
    (1320, 2868): "APP_IPHONE_67",
    (2868, 1320): "APP_IPHONE_67",
    (1290, 2796): "APP_IPHONE_67",
    (2796, 1290): "APP_IPHONE_67",
    (1260, 2736): "APP_IPHONE_67",
    (2736, 1260): "APP_IPHONE_67",
    (2064, 2752): "APP_IPAD_PRO_129",
    (2752, 2064): "APP_IPAD_PRO_129",
    (2048, 2732): "APP_IPAD_PRO_129",
    (2732, 2048): "APP_IPAD_PRO_129",
}


def screenshots():
    """Upload every PNG under fastlane/screenshots.

    Run after the CI screenshots job hands its artifact back. Files are matched
    to a display type by pixel size, so nothing needs renaming, and anything
    that is not an accepted size is reported rather than silently dropped.
    """
    try:
        from PIL import Image
    except ImportError:
        sys.exit("pip install pillow")

    app = find_app()
    if not app:
        sys.exit("no app record yet")
    version = ensure_version(app["id"])
    if not version:
        sys.exit("could not resolve version 1.0")

    root = Path(__file__).resolve().parent.parent / "fastlane" / "screenshots"
    shots = sorted(p for p in root.rglob("*.png"))
    if not shots:
        sys.exit(f"no screenshots found under {root}")

    localizations = call(
        "GET",
        f"/v1/appStoreVersions/{version['id']}/appStoreVersionLocalizations",
        params={"limit": 50},
    )
    locale_id = None
    for loc in (localizations or {}).get("data", []):
        if loc["attributes"].get("locale") == PRIMARY_LOCALE:
            locale_id = loc["id"]
    if not locale_id:
        sys.exit("no en-US localization yet; run `python Store/asc.py push-metadata`")

    sets = call(
        "GET",
        f"/v1/appStoreVersionLocalizations/{locale_id}/appScreenshotSets",
        params={"limit": 50},
    )
    set_ids = {
        s["attributes"]["screenshotDisplayType"]: s["id"]
        for s in (sets or {}).get("data", [])
    }

    uploaded = 0
    for path in shots:
        with Image.open(path) as image:
            size = image.size
        display = DISPLAY_BY_SIZE.get(size)
        if not display:
            print(f"  skip {path.name}: {size[0]}x{size[1]} is not an accepted size")
            continue

        if display not in set_ids:
            made = call(
                "POST",
                "/v1/appScreenshotSets",
                {
                    "data": {
                        "type": "appScreenshotSets",
                        "attributes": {"screenshotDisplayType": display},
                        "relationships": {
                            "appStoreVersionLocalization": {
                                "data": {
                                    "type": "appStoreVersionLocalizations",
                                    "id": locale_id,
                                }
                            }
                        },
                    }
                },
            )
            if not made:
                continue
            set_ids[display] = made["data"]["id"]

        blob = path.read_bytes()
        reserved = call(
            "POST",
            "/v1/appScreenshots",
            {
                "data": {
                    "type": "appScreenshots",
                    "attributes": {"fileName": path.name, "fileSize": len(blob)},
                    "relationships": {
                        "appScreenshotSet": {
                            "data": {
                                "type": "appScreenshotSets",
                                "id": set_ids[display],
                            }
                        }
                    },
                }
            },
        )
        if not reserved:
            continue

        # Apple returns one or more signed PUT operations to push the bytes to,
        # each covering a byte range of the file.
        ok = True
        for op in reserved["data"]["attributes"]["uploadOperations"]:
            chunk = blob[op["offset"] : op["offset"] + op["length"]]
            headers = {h["name"]: h["value"] for h in op.get("requestHeaders", [])}
            put = requests.request(
                op["method"], op["url"], headers=headers, data=chunk, timeout=180
            )
            if put.status_code >= 400:
                print(f"  ! {path.name}: upload returned {put.status_code}")
                ok = False
        if not ok:
            continue

        # The commit. Until this lands, Apple treats the reservation as garbage.
        done = call(
            "PATCH",
            f"/v1/appScreenshots/{reserved['data']['id']}",
            {
                "data": {
                    "type": "appScreenshots",
                    "id": reserved["data"]["id"],
                    "attributes": {
                        "uploaded": True,
                        "sourceFileChecksum": hashlib.md5(blob).hexdigest(),
                    },
                }
            },
        )
        if done is not None:
            uploaded += 1
            print(f"  {path.name} -> {display}")

    print(f"{uploaded} screenshot(s) uploaded")


def price(amount: str = "7.99"):
    """Set the price schedule. Base territory USA, one manual price, no end date."""
    app = find_app()
    if not app:
        sys.exit("no app record yet")
    points = call(
        "GET",
        f"/v1/apps/{app['id']}/appPricePoints",
        params={"filter[territory]": "USA", "limit": 200},
    )
    point = next(
        (
            d["id"]
            for d in (points or {}).get("data", [])
            if d["attributes"].get("customerPrice") == amount
        ),
        None,
    )
    if not point:
        sys.exit(f"no USA price point at {amount}")

    result = call(
        "POST",
        "/v1/appPriceSchedules",
        {
            "data": {
                "type": "appPriceSchedules",
                "relationships": {
                    "app": {"data": {"type": "apps", "id": app["id"]}},
                    "baseTerritory": {"data": {"type": "territories", "id": "USA"}},
                    "manualPrices": {"data": [{"type": "appPrices", "id": "${p1}"}]},
                },
            },
            "included": [
                {
                    "type": "appPrices",
                    "id": "${p1}",
                    "attributes": {"startDate": None, "endDate": None},
                    "relationships": {
                        "appPricePoint": {
                            "data": {"type": "appPricePoints", "id": point}
                        }
                    },
                }
            ],
        },
    )
    print(f"  price set to ${amount}" if result is not None else "  price failed")


def categories():
    """Primary and secondary category, and the content rights declaration.

    Content rights lives on the app resource, not on appInfo: sending it to
    appInfo returns 409 "unknown attribute", which reads like the value is wrong
    rather than the address.
    """
    app = find_app()
    if not app:
        sys.exit("no app record yet")

    call(
        "PATCH",
        f"/v1/apps/{app['id']}",
        {
            "data": {
                "type": "apps",
                "id": app["id"],
                "attributes": {
                    "contentRightsDeclaration": "DOES_NOT_USE_THIRD_PARTY_CONTENT"
                },
            }
        },
    )

    infos = call("GET", f"/v1/apps/{app['id']}/appInfos", params={"limit": 10})
    if not infos or not infos.get("data"):
        return
    info_id = infos["data"][0]["id"]
    result = call(
        "PATCH",
        f"/v1/appInfos/{info_id}",
        {
            "data": {
                "type": "appInfos",
                "id": info_id,
                "relationships": {
                    "primaryCategory": {"data": {"type": "appCategories", "id": "PRODUCTIVITY"}},
                    "secondaryCategory": {"data": {"type": "appCategories", "id": "LIFESTYLE"}},
                },
            }
        },
    )
    print("  categories set" if result is not None else "  categories failed")


def finish():
    """Everything that does not need a compiled binary."""
    print("metadata:")
    push_metadata()
    print("age rating:")
    age_rating()
    print("review details:")
    review_details()
    print("categories:")
    categories()
    print("price:")
    price(PRICE)
    print()
    status()


def leaderboards():
    """Create the two Game Center leaderboards the game submits to.

    IDs must match GameCenter.swift. Both are integer boards: the clear time is
    submitted in hundredths of a second so a "fastest" board sorts ascending
    with useful precision, and the launch is plain metres sorted descending.
    """
    app = find_app()
    if not app:
        sys.exit("no app record yet")

    detail = call("GET", f"/v1/apps/{app['id']}/gameCenterDetail", quiet=True)
    if not detail or not detail.get("data"):
        made = call("POST", "/v1/gameCenterDetails", {"data": {
            "type": "gameCenterDetails",
            "relationships": {"app": {"data": {"type": "apps", "id": app["id"]}}}}})
        if not made:
            print("  could not enable Game Center on the app")
            return
        detail_id = made["data"]["id"]
        print("  Game Center enabled on the app")
    else:
        detail_id = detail["data"]["id"]
        print("  Game Center already enabled")

    boards = [
        ("pocketbeings.fastest", "Fastest Clear", "ASC", "INTEGER"),
        ("pocketbeings.longest", "Longest Launch", "DESC", "INTEGER"),
    ]

    existing = call("GET", f"/v1/gameCenterDetails/{detail_id}/gameCenterLeaderboards",
                    params={"limit": 50}, quiet=True)
    have = {d["attributes"].get("referenceName"): d["id"]
            for d in (existing or {}).get("data", [])}

    for vendor, name, sort, fmt in boards:
        if name in have:
            print(f"  {name}: already exists")
            continue
        made = call("POST", "/v1/gameCenterLeaderboards", {"data": {
            "type": "gameCenterLeaderboards",
            "attributes": {
                "referenceName": name,
                "vendorIdentifier": vendor,
                "submissionType": "BEST_SCORE",
                "scoreSortType": sort,
                "defaultFormatter": fmt,
                "recurrenceStartDate": None,
            },
            "relationships": {"gameCenterDetail": {"data": {
                "type": "gameCenterDetails", "id": detail_id}}}}})
        if not made:
            print(f"  {name}: failed")
            continue
        board_id = made["data"]["id"]
        print(f"  {name}: created ({vendor})")

        # A board with no localisation is invisible, and Apple rejects a
        # submission that references one.
        loc = call("POST", "/v1/gameCenterLeaderboardLocalizations", {"data": {
            "type": "gameCenterLeaderboardLocalizations",
            "attributes": {"locale": PRIMARY_LOCALE, "name": name},
            "relationships": {"gameCenterLeaderboard": {"data": {
                "type": "gameCenterLeaderboards", "id": board_id}}}}})
        print(f"    localization: {'ok' if loc is not None else 'failed'}")


COMMANDS = {
    "age-rating": age_rating,
    "review-details": review_details,
    "screenshots": screenshots,
    "price": price,
    "categories": categories,
    "finish": finish,
}

if __name__ == "__main__":
    if len(sys.argv) < 2 or sys.argv[1] not in COMMANDS:
        sys.exit(f"usage: python Store/listing.py [{'|'.join(COMMANDS)}]")
    COMMANDS[sys.argv[1]]()
