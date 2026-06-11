"""Daily memory consolidation.

Reviews the day's Claude Code conversation transcripts, extracts only DURABLE
knowledge (decisions / rules / facts / config / preferences) via the Anthropic
API, dedups against what's already captured, and writes it into the single
knowledge base at le-roux-repo/system/memory/. Idempotent + catch-up: it tracks
which transcripts (by path+mtime) it has already processed.

Runs on Paul's PC (where the transcripts live) via a daily scheduled task.
See system/meta/daily-consolidation.md.

Usage:  python le-roux-repo/script/consolidate_memory.py [--since YYYY-MM-DD]
"""
import json, os, re, sys, time, urllib.request, datetime, pathlib, hashlib

HOME = pathlib.Path.home()
PROJECT_SLUG = "d--Paul-le-Roux-OneDrive-Documents-Claude-Projects-DR-CHALITA-AI-RECEPTIONIST"
TRANSCRIPTS = HOME / ".claude" / "projects" / PROJECT_SLUG
SYSTEM = pathlib.Path(__file__).resolve().parent.parent / "system"
MEMORY = SYSTEM / "memory"
STATE = MEMORY / ".consolidation_state.json"
DIGESTS = MEMORY / "digests"
KB = MEMORY / "extracted-knowledge.md"
MODEL = "claude-sonnet-4-6"

EXTRACT_PROMPT = """You are the memory consolidator for an ongoing software build (the "Ivory" dental
practice-management system). Read the conversation transcript below and extract ONLY durable,
reusable knowledge that will still matter weeks from now. Extract: decisions, rules/constraints,
definitions, conventions, config choices, durable user preferences, and important persistent TODOs.
DISCARD: status chatter, debugging steps, rejected options, one-off clarifications, anything ephemeral,
and ANY patient-identifiable data (never output PHI — names, IDs, phone numbers of patients).

Return STRICT JSON only: {"items":[{"type":"decision|rule|fact|definition|convention|config|preference|todo",
"subject":"short subject","statement":"clear standalone statement","scope":"component/area","rationale":"short or empty"}]}
If nothing durable, return {"items":[]}.

TRANSCRIPT:
"""


def api_key():
    for p in [pathlib.Path("../_shared/.env"), SYSTEM.parent.parent / "_shared" / ".env"]:
        try:
            for line in p.read_text(encoding="utf-8", errors="ignore").splitlines():
                if line.startswith("ANTHROPIC_API_KEY"):
                    return line.split("=", 1)[1].strip().strip('"')
        except Exception:
            pass
    try:
        s = json.loads((HOME / ".claude" / "settings.json").read_text())
        return s.get("env", {}).get("ANTHROPIC_API_KEY") or os.environ.get("ANTHROPIC_API_KEY")
    except Exception:
        return os.environ.get("ANTHROPIC_API_KEY")


def transcript_text(path):
    """Pull user + assistant TEXT from a Claude Code .jsonl transcript."""
    out = []
    for line in path.read_text(encoding="utf-8", errors="ignore").splitlines():
        try:
            ev = json.loads(line)
        except Exception:
            continue
        msg = ev.get("message") or {}
        role = msg.get("role") or ev.get("type")
        content = msg.get("content")
        if isinstance(content, str):
            text = content
        elif isinstance(content, list):
            text = " ".join(b.get("text", "") for b in content if isinstance(b, dict) and b.get("type") == "text")
        else:
            text = ""
        text = text.strip()
        if text and role in ("user", "assistant"):
            out.append(f"{role.upper()}: {text}")
    return "\n".join(out)


def anthropic(key, prompt):
    body = json.dumps({"model": MODEL, "max_tokens": 4000,
                       "messages": [{"role": "user", "content": prompt}]}).encode()
    req = urllib.request.Request("https://api.anthropic.com/v1/messages", data=body,
                                 headers={"x-api-key": key, "anthropic-version": "2023-06-01",
                                          "content-type": "application/json"})
    r = json.load(urllib.request.urlopen(req, timeout=180))
    return "".join(b.get("text", "") for b in r.get("content", []))


def norm(s):
    return re.sub(r"[^a-z0-9 ]", "", s.lower()).strip()


def main():
    key = api_key()
    if not key:
        print("No ANTHROPIC_API_KEY found"); sys.exit(1)
    if not TRANSCRIPTS.exists():
        print(f"No transcripts dir: {TRANSCRIPTS}"); sys.exit(0)
    MEMORY.mkdir(parents=True, exist_ok=True); DIGESTS.mkdir(exist_ok=True)
    state = json.loads(STATE.read_text()) if STATE.exists() else {"processed": {}}
    seen = set()
    if KB.exists():
        seen = {norm(l) for l in KB.read_text(encoding="utf-8", errors="ignore").splitlines() if l.startswith("- ")}

    today = datetime.date.today().isoformat()
    limit = int(os.environ.get("CONSOLIDATE_MAX", "0")) or None  # cap transcripts/run (testing)
    digest_items, processed_now = [], 0

    def append_kb(items):
        first = (not KB.exists()) or KB.stat().st_size == 0
        with KB.open("a", encoding="utf-8") as kb:
            if first:
                kb.write("# Extracted knowledge (auto-consolidated)\n\n")
            for it in items:
                rat = (" — _" + it["rationale"] + "_") if it.get("rationale") else ""
                kb.write(f"- **[{it.get('type','fact')}] {it.get('subject','')}** "
                         f"({it.get('scope','')}): {it.get('statement','')}{rat}  <sub>{today}</sub>\n")

    for f in sorted(TRANSCRIPTS.glob("*.jsonl")):
        if limit and processed_now >= limit:
            break
        mtime = f.stat().st_mtime
        if state["processed"].get(f.name) == mtime:
            continue  # already done at this version
        text = transcript_text(f)
        if len(text) < 200:
            state["processed"][f.name] = mtime
            STATE.write_text(json.dumps(state, indent=2))
            continue
        try:
            raw = anthropic(key, EXTRACT_PROMPT + text[-120000:])
            m = re.search(r"\{.*\}", raw, re.S)
            items = json.loads(m.group(0))["items"] if m else []
        except Exception as e:
            print(f"  extract failed for {f.name}: {e}"); continue
        fresh = []
        for it in items:
            stmt = it.get("statement", "").strip()
            if not stmt or norm(stmt) in seen:
                continue
            seen.add(norm(stmt)); fresh.append(it)
        if fresh:
            append_kb(fresh); digest_items += fresh
        state["processed"][f.name] = mtime
        state["last_run"] = today
        STATE.write_text(json.dumps(state, indent=2))  # persist per-transcript (resumable)
        processed_now += 1
        print(f"  {f.name}: +{len(fresh)} item(s)")

    if digest_items:
        with (DIGESTS / f"{today}.md").open("w", encoding="utf-8") as d:
            d.write(f"# Daily knowledge digest — {today}\n\n{processed_now} transcript(s), "
                    f"{len(digest_items)} new durable item(s).\n\n")
            for it in digest_items:
                d.write(f"- **[{it.get('type')}] {it.get('subject')}**: {it.get('statement')}\n")
    print(f"[consolidate] {today}: {processed_now} transcript(s), {len(digest_items)} new item(s) -> system/memory/")


if __name__ == "__main__":
    main()
