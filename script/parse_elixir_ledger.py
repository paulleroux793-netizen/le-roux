"""Elixir recent ledger -> Ivory invoices (grouped Debit by account+date, with the
treating PROVIDER) + payments (Credit). Maps account_cl -> REAL code (internal.json).
Usage: parse_elixir_ledger.py <ledger_raw> <internal.json> <ledger.json>"""
import json, re, sys
MON = {'JAN':1,'FEB':2,'MAR':3,'APR':4,'MAY':5,'JUN':6,'JUL':7,'AUG':8,'SEP':9,'OCT':10,'NOV':11,'DEC':12}
def iso(s):
    m = re.match(r"(\d{1,2})-([A-Z]{3})-(\d{4})", s.strip())
    return f"{m.group(3)}-{MON[m.group(2)]:02d}-{int(m.group(1)):02d}" if m else None
def clean(s): return re.sub(r"[^\x20-\x7e]", "-", s).strip()
def pay_method(narr):
    u = narr.upper()
    return "card" if "CARD" in u else "cash" if "CASH" in u else "eft"
internal = json.load(open(sys.argv[2], encoding="utf-8"))   # account_cl -> real code
invoices, payments = {}, []
for line in open(sys.argv[1], encoding="latin-1"):
    if "|@|" not in line: continue
    p = [x.strip() for x in line.rstrip("\n").split("|@|")]
    if len(p) < 7: continue
    acct_cl, dos, itype, amt, vat, narr, code = p[:7]
    provider = clean(p[7]) if len(p) > 7 else ""
    acode = internal.get(acct_cl)
    if not acode: continue
    d = iso(dos)
    try: amount = float(amt)
    except ValueError: continue
    try: vatv = float(vat) if vat else 0.0
    except ValueError: vatv = 0.0
    if itype.lower() == "debit":
        key = f"{acode}|{d}"
        inv = invoices.setdefault(key, {"account_code": acode, "date": d, "lines": [], "_prov": {}})
        inv["lines"].append({"code": code or None, "description": clean(narr), "amount": amount, "vat": vatv})
        if provider: inv["_prov"][provider] = inv["_prov"].get(provider, 0) + 1
    elif itype.lower() == "credit":
        payments.append({"account_code": acode, "date": d, "amount": amount, "method": pay_method(narr)})
for inv in invoices.values():
    pv = inv.pop("_prov", {})
    inv["provider"] = max(pv, key=pv.get) if pv else None
out = {"invoices": list(invoices.values()), "payments": payments}
json.dump(out, open(sys.argv[3], "w", encoding="utf-8"), ensure_ascii=False)
provd = sum(1 for i in out["invoices"] if i["provider"])
print(f"{len(out['invoices'])} invoices ({provd} w/ provider), {len(out['payments'])} payments")
