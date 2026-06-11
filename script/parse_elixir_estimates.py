"""Parses the Elixir estimates dump into JSON for the Ivory estimate mirror,
mapping each estimate's Elixir account (CL-code) to the alphabetical A-code so
estimates show under the right patient/account.

Usage: python parse_elixir_estimates.py <estimates_raw.txt> <patients.json> <estimates.json>
Input row: dateof(DD-MON-YYYY) | account_cl | patient_name | valueof | details | status
"""
import json, re, sys

MON = {'JAN':1,'FEB':2,'MAR':3,'APR':4,'MAY':5,'JUN':6,
       'JUL':7,'AUG':8,'SEP':9,'OCT':10,'NOV':11,'DEC':12}


def iso(s):
    m = re.match(r"(\d{1,2})-([A-Z]{3})-(\d{4})", s.strip())
    return f"{m.group(3)}-{MON[m.group(2)]:02d}-{int(m.group(1)):02d}" if m else None


def main(src, patients_json, dst):
    patients = json.load(open(patients_json, encoding="utf-8"))
    acct_map = {p["account_cl"]: p["account_code"]
                for p in patients if p.get("account_cl") and p.get("account_code")}
    rows = []
    for line in open(src, encoding="latin-1"):
        if "|@|" not in line:
            continue
        p = [x.strip() for x in line.rstrip("\n").split("|@|")]
        if len(p) < 6:
            continue
        try:
            value = float(p[3]) if p[3] else 0.0
        except ValueError:
            value = 0.0
        rows.append({
            "date_sent": iso(p[0]),
            "account_code": acct_map.get(p[1]),
            "patient_name": p[2].title(),
            "value": value,
            "details": p[4],
            "legend": p[5] or None,
        })
    json.dump(rows, open(dst, "w", encoding="utf-8"), ensure_ascii=False)
    mapped = sum(1 for r in rows if r["account_code"])
    print(f"parsed {len(rows)} estimates ({mapped} mapped to an A-code) -> {dst}")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2], sys.argv[3])
