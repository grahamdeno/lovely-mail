#!/usr/bin/env python3
"""Privacy guard for Lovely's Gmail access (per-endpoint allowlist).

Approved 2026-11-01: gmail.modify for Trash and Done.
Approved 2026-11-04 (Sprint 6): filters, sending and Lovely/ labels, only in GmailActions.swift,
each behind a ConfirmedAction made by the preview sheet. Forwarding addresses are read only (GET); Gmail's create call
works only for Workspace service accounts, and the owner adds addresses in Gmail's own Settings.
Approved 2026-11-08 (Sprint 7, inbox session): the session's own action button is the preview. It shows exactly
what will happen (which messages, which drawer) and makes the ConfirmedAction in SessionConfirm.swift, so putting
mail away is one tap. Cloud language models (Anthropic, xAI) may be called only from Session/Engines/CloudEngines.swift.
Never allowed: permanent delete, the full-access scope, other Gmail settings.

  check     Scan App/Reelmail and fail on any violation.
  selftest  Prove the rules catch bad code and pass good code (no Xcode needed).
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "App" / "Reelmail"
ACTIONS = "Gmail/GmailActions.swift"
SERVICE = "Gmail/GmailService.swift"
CONFIG = "Gmail/GmailConfig.swift"
SHEET = "Features/Actions/ActionPreviewSheet.swift"
GUARDS = "Gmail/ActionGuards.swift"
SESSION_CONFIRM = "Features/Session/SessionConfirm.swift"
CLOUD = "Session/Engines/CloudEngines.swift"
# UI audit fixtures: a fake Gmail for simulator tests. Debug builds only; release builds must neither contain nor reach it.
FIXTURES = "Fixtures/UITestFixtures.swift"
FIXTURE_SYMBOLS = r"\b(FixtureMode|FixtureGmailClient|FixtureLog|FixtureRequestsOverlay|FixtureData|FixtureRecorder)\b|uiTestFixtures|uiTest(Expired|NoPermission|Offline|Empty|SignedOut|Appearance)"

# Helpers in GmailActions.swift that do not change anything by themselves.
HELPERS = {"request", "call", "deliver", "encode", "init"}
# Read-only functions in GmailActions.swift: no ConfirmedAction, and every call in them must be a GET.
READ_ONLY = {"forwardingStatus", "existingLabelID"}


def strip_comments(text):
    return "\n".join(re.sub(r"(?<!:)//.*$", "", line) for line in text.splitlines())


def without_debug_regions(text):
    """The text with every line inside `#if DEBUG` removed (the `#else` side of it stays: that is the release build)."""
    kept, stack = [], []
    for line in text.splitlines():
        t = line.strip()
        if t.startswith("#if"):
            stack.append("debug" if re.fullmatch(r"#if\s+DEBUG\s*", t) else "release" if re.fullmatch(r"#if\s+!\s*DEBUG\s*", t) else "other")
            kept.append("")
        elif t.startswith("#else") and stack:
            stack[-1] = {"debug": "release", "release": "debug"}.get(stack[-1], "other")
            kept.append("")
        elif t.startswith("#endif") and stack:
            stack.pop(); kept.append("")
        else:
            kept.append("" if "debug" in stack else line)
    return "\n".join(kept)


def check_fixture_file(text):
    """The fixture file must be wrapped entirely in `#if DEBUG` and must never open a network connection."""
    bad = []
    code = [l.strip() for l in strip_comments(text).splitlines() if l.strip()]
    if not code or code[0] != "#if DEBUG" or code[-1] != "#endif":
        bad.append(f"{FIXTURES}: the whole file must sit inside #if DEBUG ... #endif.")
    if any(l.startswith("#else") or l.startswith("#elseif") for l in code):
        bad.append(f"{FIXTURES}: no #else or #elseif: the file must not exist in release builds at all.")
    if any(l.startswith("#if") and l != "#if DEBUG" for l in code[1:]) or sum(1 for l in code if l.startswith("#if")) != sum(1 for l in code if l.startswith("#endif")):
        bad.append(f"{FIXTURES}: only one #if DEBUG, closed once, at the ends of the file.")
    if re.search(r"URLSession|URLConnection|NWConnection|CFNetwork", strip_comments(text)):
        bad.append(f"{FIXTURES}: fixtures must not open network connections.")
    return bad


def check(files):
    """files: {relative path: text}. Returns a list of violation strings."""
    bad = []
    for rel, raw in files.items():
        text = strip_comments(raw)
        if rel == FIXTURES:
            bad.extend(check_fixture_file(raw))
        else:
            release_text = without_debug_regions(text)
            for m in re.finditer(FIXTURE_SYMBOLS, release_text):
                bad.append(f"{rel}:{release_text[: m.start()].count(chr(10)) + 1}: Fixture mode may be named only inside #if DEBUG (release builds must not reach it).")
        def hit(pattern, message, allowed=()):
            if rel in allowed:
                return
            for m in re.finditer(pattern, text):
                line = text[: m.start()].count("\n") + 1
                bad.append(f"{rel}:{line}: {message}")

        hit(r"batchDelete|batchModify", "Batch delete or batch modify is never allowed.")
        hit(r'https://mail\.google\.com/["\s]', "The full-access Gmail scope is never allowed.")
        hit(r"/settings/(vacation|imap|pop|delegates|autoForwarding|sendAs|cse|language)", "Only filters and forwarding addresses may be changed in Gmail settings.")
        hit(r'"DELETE"', "DELETE is allowed only in GmailActions.swift (for filters Lovely made).", allowed=(ACTIONS,))
        hit(r"/messages/send|/settings/filters|/settings/forwardingAddresses|/labels|/drafts", "This Gmail endpoint may be used only in GmailActions.swift.", allowed=(ACTIONS,))
        hit(r"/modify\b", "The modify endpoint may be used only in GmailService.swift and GmailActions.swift.", allowed=(SERVICE, ACTIONS))
        hit(r"gmail\.(modify|send|settings\.basic|settings\.sharing|compose|readonly)", "Gmail scopes may be named only in GmailConfig.swift.", allowed=(CONFIG,))
        hit(r"ConfirmedAction\(|ConfirmedAction\.init|\.init\(preview:", "ConfirmedAction may be made only by the preview sheet or the session's action button.", allowed=(SHEET, GUARDS, SESSION_CONFIRM))
        hit(r"api\.anthropic\.com|api\.x\.ai", "Cloud language models may be called only from CloudEngines.swift.", allowed=(CLOUD,))
        hit(r"googleapis\.com/auth/", "OAuth scopes may be named only in GmailConfig.swift.", allowed=(CONFIG,))
        hit(r"(?<![\w.])gmail\.(labels|metadata|insert|addons|settings)", "Gmail scopes may be named only in GmailConfig.swift.", allowed=(CONFIG,))
        hit(r"gmail\.googleapis\.com", "The Gmail API may be called only from GmailService.swift and GmailActions.swift.", allowed=(SERVICE, ACTIONS))
        hit(r"/messages/(import|insert)|/import\b|/insert\b|/settings/forwarding\b|/stop\b|/watch\b", "Importing, inserting, auto-forwarding and push watch are never allowed.")
        hit(r'"(send|labels|filters|forwardingAddresses|settings|drafts)"', "Gmail endpoint names may appear only in GmailActions.swift.", allowed=(ACTIONS, FIXTURES))
        if rel != ACTIONS:
            for m in re.finditer(r"LabelIds", text):
                window = text[m.start(): m.start() + 40]
                if not re.match(r'LabelIds\\?"?\s*:\s*\[\\?"UNREAD\\?"\]', window):
                    bad.append(f"{rel}:{text[: m.start()].count(chr(10)) + 1}: Outside GmailActions.swift only the UNREAD label may change.")
        else:
            for m in re.finditer(r"removeLabelIds[^\n]*", text):
                # Approved Nov 9, 2026: the category re-sort may remove Lovely-owned labels, in relabel() only,
                # which checks every id with labels.isLovely first.
                if '["INBOX"]' not in m.group(0) and 'removeLabelIds": lovelyOnlyRemovals' not in m.group(0):
                    bad.append(f"{rel}:{text[: m.start()].count(chr(10)) + 1}: removeLabelIds may remove INBOX only.")
            for m in re.finditer(r'"DELETE"[^\n]*', text):
                pass
            for m in re.finditer(r"call\(\"DELETE\",\s*\"([^\"]*)", text):
                if "/settings/filters/" not in m.group(1):
                    bad.append(f"{rel}:{text[: m.start()].count(chr(10)) + 1}: DELETE may remove filters only.")
            for m in re.finditer(r'call\("(\w+)",\s*"/settings/forwardingAddresses', text):
                if m.group(1) != "GET":
                    bad.append(f"{rel}:{text[: m.start()].count(chr(10)) + 1}: Forwarding addresses may only be read (GET).")
            # Every changing function takes a ConfirmedAction.
            for m in re.finditer(r"\bfunc\s+(\w+)\s*(?:<[^>]*>)?\s*\(([^{]*)\{", text, re.S):
                name, signature = m.group(1), m.group(2)
                if name in HELPERS:
                    continue
                if name in READ_ONLY:
                    nxt = re.search(r"\n\s*(?:private\s+)?(?:func|struct|// MARK)\b", text[m.end():])
                    body = text[m.end(): m.end() + nxt.start()] if nxt else text[m.end():]
                    for c in re.finditer(r'call\("(\w+)"', body):
                        if c.group(1) != "GET":
                            bad.append(f"{rel}:{text[: m.start()].count(chr(10)) + 1}: func {name} is read-only and may only GET.")
                    continue
                if "ConfirmedAction" not in signature:
                    bad.append(f"{rel}:{text[: m.start()].count(chr(10)) + 1}: func {name} must take a ConfirmedAction.")
    return bad


def load():
    files = {}
    for p in SRC.rglob("*.swift"):
        files[p.relative_to(SRC).as_posix()] = p.read_text()
    return files


def selftest():
    good_actions = '''
struct GmailActions {
    func ensureLabel(_ name: String, confirmed: ConfirmedAction) async throws -> String { "" }
    func deleteFilter(id: String, confirmed: ConfirmedAction) async throws { try await call("DELETE", "/settings/filters/x") }
    func file(messageID: String, confirmed: ConfirmedAction) async throws { body["removeLabelIds"] = ["INBOX"] ; call("POST", "/messages/x/modify") }
    func request(_ method: String) throws -> Int { 0 }
    func forwardingStatus() async throws -> [Int] { let l: L = try await call("GET", "/settings/forwardingAddresses"); return [] }
}
'''
    ok = {ACTIONS: good_actions, SERVICE: 'path = "/modify"; json = "{\\"addLabelIds\\":[\\"UNREAD\\"]}"', CONFIG: 'let modify = "https://www.googleapis.com/auth/gmail.modify"'}
    assert check(ok) == [], check(ok)
    cases = {
        "send outside actions": {"Model/X.swift": 'let u = "/messages/send"'},
        "batch delete": {"Model/X.swift": 'let u = "batchDelete"'},
        "full access scope": {"Model/X.swift": 'let s = "https://mail.google.com/"'},
        "vacation settings": {ACTIONS: good_actions, "Model/X.swift": 'let u = "/settings/vacation"'},
        "delete outside actions": {"Model/X.swift": 'm = "DELETE"'},
        "scope outside config": {"Model/X.swift": 'let s = "gmail.send"'},
        "label other than unread": {SERVICE: '{"addLabelIds":["STARRED"]}'},
        "confirmed made elsewhere": {"Model/X.swift": "let c = ConfirmedAction(preview: p)"},
        "unconfirmed changing func": {ACTIONS: good_actions + "\nstruct Y { func sendNow(to: String) async throws {} }"},
        "remove label other than inbox": {ACTIONS: good_actions.replace('["INBOX"]', '["UNREAD"]')},
        "delete message in actions": {ACTIONS: good_actions.replace("/settings/filters/x", "/messages/x")},
        "confirmed via init": {"Model/X.swift": "let c: ConfirmedAction = .init(preview: p)"},
        "confirmed in another session file": {"Features/Session/SessionView.swift": "let c = ConfirmedAction(preview: p)"},
        "cloud model from elsewhere": {"Model/X.swift": 'let u = "https://api.anthropic.com/v1/messages"'},
        "grok from elsewhere": {"Session/Engines/Other.swift": 'let u = "https://api.x.ai/v1/chat/completions"'},
        "other scope": {"Model/X.swift": 'let s = "https://www.googleapis.com/auth/gmail.labels"'},
        "api from elsewhere": {"Model/X.swift": 'let u = "https://gmail.googleapis.com/gmail/v1/users/me/messages"'},
        "insert message": {"Model/X.swift": 'let u = base + "/messages/insert"'},
        "auto forwarding": {ACTIONS: good_actions + '\nlet u = "/settings/forwarding"'},
        "forwarding address create": {ACTIONS: good_actions.replace('call("GET", "/settings/forwardingAddresses")', 'call("POST", "/settings/forwardingAddresses")')},
        "read-only func that writes": {ACTIONS: good_actions.replace('call("GET", "/settings/forwardingAddresses")', 'call("POST", "/settings/filters")')},
        "unconfirmed forwarding create": {ACTIONS: good_actions + '\nstruct Z { func addForwarding() async throws { call("GET", "/settings/forwardingAddresses") } }'},
        "endpoint built from parts": {"Model/X.swift": 'let u = "/messages/" + "send"'},
        "fixture named in release code": {"Model/X.swift": "let s = FixtureMode.makeStoreIfRequested()"},
        "fixture flag in release code": {"Model/X.swift": 'let on = args.contains("-uiTestFixtures")'},
        "fixture after the debug block ends": {"Model/X.swift": "#if DEBUG\nlet a = 1\n#endif\nlet s = FixtureGmailClient()"},
        "fixture on the not-debug side": {"Model/X.swift": "#if DEBUG\nlet a = 1\n#else\nlet s = FixtureData.inbox()\n#endif"},
        "fixture under a different condition": {"Model/X.swift": "#if TESTING\nlet s = FixtureData.inbox()\n#endif"},
        "fixture file not wrapped": {FIXTURES: "enum FixtureData {}"},
        "fixture file with a release side": {FIXTURES: "#if DEBUG\nenum FixtureData {}\n#else\nenum FixtureData {}\n#endif"},
        "fixture file with a second condition": {FIXTURES: "#if DEBUG\n#if os(iOS)\nenum A {}\n#endif\n#endif"},
        "fixture file with network": {FIXTURES: "#if DEBUG\nlet s = URLSession.shared\n#endif"},
    }
    for name, files in cases.items():
        assert check(files), f"guard missed: {name}"
    # Fixture mode is allowed inside #if DEBUG, in other files and in its own file.
    assert check({"Model/X.swift": "#if DEBUG\nlet s = FixtureMode.makeStoreIfRequested()\n#endif\nlet t = 1", FIXTURES: "#if DEBUG\nenum FixtureData { let a = \"labels\" }\n#endif"}) == []
    assert check({"Model/X.swift": "#if !DEBUG\nlet t = 1\n#else\nlet s = FixtureMode.isRequested\n#endif"}) == []
    # The session's action button and the cloud engine file are allowed their one exception each.
    assert check({SESSION_CONFIRM: "let c = ConfirmedAction(preview: p)", CLOUD: 'let u = "https://api.anthropic.com/v1/messages"'}) == []
    # Comments never trip the guard.
    assert check({"Model/X.swift": "// we never call /messages/send here"}) == []
    print("privacy_guard selftest: ok")


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "check"
    if cmd == "selftest":
        selftest()
    elif cmd == "check":
        problems = check(load())
        for p in problems:
            print(f"::error::{p}")
        if problems:
            sys.exit(1)
        print("privacy_guard: ok")
    else:
        sys.exit("usage: privacy_guard.py check|selftest")
