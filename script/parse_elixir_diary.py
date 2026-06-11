"""Parses the pipe-delimited Elixir diary dump (from extract_elixir_diary.sql)
into clean JSON for the Ivory mirror import (import_elixir_live.rb).

Usage: python parse_elixir_diary.py <diary_raw.txt> <diary_live.json>
Maps RESOURCEID -> dentist, parses CAPTION -> patient_name / account_code /
is_new_patient, and MESSAGE1 -> reason.
"""
import json, re, sys

MON = {'JAN':1,'FEB':2,'MAR':3,'APR':4,'MAY':5,'JUN':6,
       'JUL':7,'AUG':8,'SEP':9,'OCT':10,'NOV':11,'DEC':12}
DENT = {'1':'Dr Chalita le Roux', '2':'Dr Anneze Odendaal', '3':'Dr Eric Heyl',
        '4':'Dr Theo Botha', '5':'Dr Eliska Robinson'}


def parse_dt(s):
    m = re.match(r'(\d{1,2})-([A-Z]{3})-(\d{4})\s+(\d{1,2}):(\d{2}):(\d{2})', s.strip())
    if not m:
        return None
    d, mon, y, H, Mi, S = m.groups()
    return f"{int(y):04d}-{MON[mon]:02d}-{int(d):02d}T{int(H):02d}:{int(Mi):02d}:{int(S):02d}"


def parse_caption(cap):
    cap = cap.strip()
    name, acct, newp = cap, None, False
    m = re.search(r'\[([^\]]+)\]\s*$', cap)
    if m:
        tag = m.group(1).strip()
        name = cap[:m.start()].strip()
        if tag.lower().startswith('new'):
            newp = True
        elif re.match(r'^[A-Za-z]\d+$', tag):
            acct = tag
    return name, acct, newp


def main(src, dst):
    rows = []
    seen = set()
    with open(src, 'r', encoding='latin-1') as f:
        for line in f:
            if '|@|' not in line:
                continue
            p = line.rstrip('\n').split('|@|')
            if len(p) < 5:
                continue
            start = parse_dt(p[0])
            if not start:
                continue
            dedupe_key = '|'.join(x.strip() for x in p[:5])
            if dedupe_key in seen:   # guard against any duplicate extraction lines
                continue
            seen.add(dedupe_key)
            name, acct, newp = parse_caption(p[3])
            rows.append({
                'diary_date': start[:10],
                'appointment_start_at': start,
                'appointment_end_at': parse_dt(p[1]),
                'dentist': DENT.get(p[2].strip(), f"Resource {p[2].strip()}"),
                'patient_name': name,
                'account_code': acct,
                'is_new_patient': newp,
                'reason': (p[4].strip() or None),
            })
    with open(dst, 'w', encoding='utf-8') as f:
        json.dump(rows, f, ensure_ascii=False)
    print(f"parsed {len(rows)} rows -> {dst} "
          f"({sum(1 for r in rows if r['is_new_patient'])} new patients)")


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
