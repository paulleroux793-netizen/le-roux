"""Elixir billed line-items -> current tariff fee per code (the latest billed
AMOUNT, VAT-inclusive). Filters out payment/credit entries. -> tariffs.json"""
import json, re, sys
MON = {'JAN':1,'FEB':2,'MAR':3,'APR':4,'MAY':5,'JUN':6,'JUL':7,'AUG':8,'SEP':9,'OCT':10,'NOV':11,'DEC':12}
def dnum(s):
    m = re.match(r"(\d{1,2})-([A-Z]{3})-(\d{4})", s.strip())
    return int(m.group(3))*10000 + MON[m.group(2)]*100 + int(m.group(1)) if m else 0
def clean(s):
    return re.sub(r"[^\x20-\x7e]", "-", s).strip()
best = {}
for line in open(sys.argv[1], encoding="latin-1"):
    if "|@|" not in line: continue
    p = [x.strip() for x in line.rstrip("\n").split("|@|")]
    if len(p) < 5: continue
    code, narr, amt, dos, vat = p[:5]
    if not re.match(r"^\d", code): continue           # real tariff codes start numeric (skips P-CARD etc.)
    u = narr.upper()
    if "PAYMENT" in u or "CREDIT CARD" in u or "RECEIVED" in u: continue
    try: amount = float(amt)
    except ValueError: continue
    if amount <= 0: continue
    d = dnum(dos)
    if code not in best or (d, amount) > (best[code][0], best[code][1]):
        best[code] = (d, amount, clean(narr), vat.strip())
rows = [{"code": c, "description": v[2], "fee": v[1], "vat": v[3]} for c, v in best.items()]
json.dump(rows, open(sys.argv[2], "w", encoding="utf-8"), ensure_ascii=False)
print(f"{len(rows)} tariff codes with latest fee")
