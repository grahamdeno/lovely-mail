#!/usr/bin/env python3
"""Gmail configuration gate for Reelmail release builds.

  prepare --mode gmail|demo         Write Config/Local.xcconfig for the archive.
                                    gmail: copy the client ID from Config/Release.xcconfig; fail if it is missing or malformed.
                                    demo:  write an empty client ID on purpose (fictional sample mail).
  verify-app APP --mode gmail|demo  Read the built app's Info.plist and confirm the effective value.
  selftest                          Run this script's own checks (no Xcode needed).

Client IDs are public by design for iOS OAuth clients. No secrets pass through this script.
"""
import argparse
import plistlib
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RELEASE = ROOT / "Config" / "Release.xcconfig"
LOCAL = ROOT / "Config" / "Local.xcconfig"
SWIFT_CONFIG = ROOT / "App" / "Reelmail" / "Gmail" / "GmailConfig.swift"
KEY = "GOOGLE_IOS_CLIENT_ID"
PLIST_KEY = "GoogleIOSClientID"
BUNDLE_ID = "com.grahamdeno.reelmail"
# Must match GmailConfig.clientIDPattern (selftest enforces this).
PATTERN = r"^[0-9]+-[A-Za-z0-9_]+\.apps\.googleusercontent\.com$"


def fail(message):
    print(f"::error::{message}")
    sys.exit(1)


def is_valid(client_id):
    return not client_id.startswith("YOUR_") and re.fullmatch(PATTERN, client_id) is not None


def redirect_scheme(client_id):
    return ".".join(reversed(client_id.split(".")))


def read_xcconfig_value(text, key=KEY):
    value = None
    for line in text.splitlines():
        line = line.split("//", 1)[0].strip()
        m = re.fullmatch(rf"{key}\s*=\s*(.*)", line)
        if m:
            value = m.group(1).strip()
    return value


def prepare(mode):
    if LOCAL.exists():
        fail("Config/Local.xcconfig already exists; refusing to overwrite it.")
    if mode == "demo":
        LOCAL.write_text(f"// Written by CI: explicit fictional-demo build.\n{KEY} =\n")
        print("::warning::Demo build requested: Gmail is intentionally unconfigured and the app shows sample mail.")
        return
    value = read_xcconfig_value(RELEASE.read_text()) if RELEASE.exists() else None
    if not value:
        fail("Config/Release.xcconfig has no Google iOS client ID. A TestFlight build would be stuck in sample mode. "
             "Add the iOS OAuth client ID for com.grahamdeno.reelmail, or run the workflow with demo_build=true.")
    if not is_valid(value):
        fail("The client ID in Config/Release.xcconfig is not a valid Google OAuth client ID.")
    LOCAL.write_text(f"// Written by CI from Config/Release.xcconfig.\n{KEY} = {value}\n")
    print(f"Gmail release config ready. Redirect scheme: {redirect_scheme(value)}")


def verify_app(app, mode, expected=None):
    plist_path = Path(app) / "Info.plist"
    if not plist_path.exists():
        fail(f"No Info.plist in {app}")
    with plist_path.open("rb") as f:
        info = plistlib.load(f)
    if info.get("CFBundleIdentifier") != BUNDLE_ID:
        fail(f"Unexpected bundle identifier {info.get('CFBundleIdentifier')!r}")
    if PLIST_KEY not in info:
        fail(f"{PLIST_KEY} is missing from the built Info.plist")
    value = str(info[PLIST_KEY]).strip()
    if "$(" in value:
        fail(f"{PLIST_KEY} was not expanded in the built Info.plist")
    if mode == "demo":
        if value:
            fail("Demo build expected an empty client ID but the app is configured.")
        print("Verified: built app is an explicit demo build (sample mail).")
        return
    if not is_valid(value):
        fail(f"The built app's {PLIST_KEY} is empty or malformed; it would launch in sample mode.")
    if expected is None and RELEASE.exists():
        expected = read_xcconfig_value(RELEASE.read_text())
    if expected and value != expected:
        fail("The built app's client ID does not match Config/Release.xcconfig.")
    print(f"Verified: build {info.get('CFBundleVersion')} is configured for Gmail; "
          f"redirect {redirect_scheme(value)}:/oauthredirect")


def verify_icon(app):
    """The compiled app must carry the AppIcon from AppIcon.icon and the Lovely display name."""
    app = Path(app)
    with (app / "Info.plist").open("rb") as f:
        info = plistlib.load(f)
    primary = info.get("CFBundleIcons", {}).get("CFBundlePrimaryIcon", {})
    name = primary.get("CFBundleIconName") if isinstance(primary, dict) else None
    if name != "AppIcon":
        fail(f"Built app has no AppIcon (CFBundleIconName={name!r}); the Liquid Glass icon did not compile.")
    if not (app / "Assets.car").exists():
        fail("Built app has no Assets.car; the icon was not compiled.")
    if info.get("CFBundleDisplayName") != "Lovely":
        fail(f"Display name is {info.get('CFBundleDisplayName')!r}, expected 'Lovely'.")
    print("Verified: AppIcon compiled into Assets.car; display name Lovely")


def selftest():
    swift = SWIFT_CONFIG.read_text()
    m = re.search(r'clientIDPattern = #"(.+?)"#', swift)
    assert m and m.group(1) == PATTERN, "Python and Swift client ID patterns differ"
    assert is_valid("123-abc.apps.googleusercontent.com")
    assert is_valid("456735134102-jc712gcpnljkbme25bu6p2l2ivjv6330.apps.googleusercontent.com")
    for bad in ["", "$(GOOGLE_IOS_CLIENT_ID)", "YOUR_CLIENT_ID.apps.googleusercontent.com",
                "123-abc.apps.googleusercontent.com.evil", " 123-abc.apps.googleusercontent.com",
                "abc.apps.googleusercontent.com", "123-abc"]:
        assert not is_valid(bad), bad
    assert redirect_scheme("123-abc.apps.googleusercontent.com") == "com.googleusercontent.apps.123-abc"
    assert read_xcconfig_value("// x\nGOOGLE_IOS_CLIENT_ID =\n") == ""
    assert read_xcconfig_value("GOOGLE_IOS_CLIENT_ID = 1-a.apps.googleusercontent.com // note") == "1-a.apps.googleusercontent.com"
    assert read_xcconfig_value("OTHER = 1") is None
    print("gmail_release_config selftest passed")


def main():
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)
    p = sub.add_parser("prepare"); p.add_argument("--mode", choices=["gmail", "demo"], required=True)
    v = sub.add_parser("verify-app"); v.add_argument("app"); v.add_argument("--mode", choices=["gmail", "demo"], required=True)
    sub.add_parser("selftest")
    i = sub.add_parser("verify-icon"); i.add_argument("app")
    args = parser.parse_args()
    if args.command == "prepare":
        prepare(args.mode)
    elif args.command == "verify-app":
        verify_app(args.app, args.mode)
        verify_icon(args.app)
    elif args.command == "verify-icon":
        verify_icon(args.app)
    else:
        selftest()


if __name__ == "__main__":
    main()
