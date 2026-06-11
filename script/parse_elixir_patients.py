"""Parses the Elixir patient dump (DEPENDANTS joined to ACCOUNTS, from the
patients SQL) into clean JSON for the Ivory patient import.

Assigns each ACCOUNT (family) an alphabetical account number: surname-initial +
zero-padded sequence, in surname order (A0001, A0002, …, B0001, …) so the
patient list organises A→Z by account number (Paul's requirement, 2026-06-05).

Usage: python parse_elixir_patients.py <patients_raw.txt> <patients.json>
Input fields per |@|-delimited row:
  firstname | surname | nidn | cellular | birthdate(DD/MM/YYYY) | relation |
  account_cl | email | telephonehome | account_surname
"""
import json, re, sys


def iso_dob(s):
    m = re.match(r"(\d{2})/(\d{2})/(\d{4})", s.strip())
    return f"{m.group(3)}-{m.group(2)}-{m.group(1)}" if m else None


def main(src, dst):
    rows = []
    with open(src, "r", encoding="latin-1") as f:
        for line in f:
            if "|@|" not in line:
                continue
            p = [x.strip() for x in line.rstrip("\n").split("|@|")]
            if len(p) < 10:
                continue
            first, surname, nidn, cell, dob, relation, acct_cl, email, telh, acct_sn = p[:10]
            if not surname or not first:
                continue
            rows.append({
                "first_name": first.title(),
                "last_name": surname.title(),
                "id_number": (nidn if re.fullmatch(r"\d{6,13}", nidn or "") else None),
                "phone": (cell or telh) or None,
                "date_of_birth": iso_dob(dob),
                "relation": relation or None,
                "email": (email or None),
                "account_cl": acct_cl or None,
                "account_surname": (acct_sn or surname).title(),
                "is_head": bool(relation and "MAIN" in relation.upper()),
            })

    # Assign alphabetical account numbers per ACCOUNT (one code per family).
    accounts = {}
    for r in rows:
        key = r["account_cl"] or f"_self_{r['last_name']}_{r['first_name']}"
        accounts.setdefault(key, {"surname": r["account_surname"], "rows": []})["rows"].append(r)
    ordered = sorted(accounts.items(), key=lambda kv: (kv[1]["surname"].upper(), kv[0]))
    per_initial = {}
    for key, acc in ordered:
        initial = (acc["surname"][:1] or "Z").upper()
        if not initial.isalpha():
            initial = "Z"
        per_initial[initial] = per_initial.get(initial, 0) + 1
        acc["account_code"] = f"{initial}{per_initial[initial]:04d}"
        for r in acc["rows"]:
            r["account_code"] = acc["account_code"]

    json.dump(rows, open(dst, "w", encoding="utf-8"), ensure_ascii=False)
    heads = sum(1 for r in rows if r["is_head"])
    with_id = sum(1 for r in rows if r["id_number"])
    print(f"parsed {len(rows)} patients across {len(accounts)} accounts "
          f"({heads} account heads, {with_id} with ID numbers) -> {dst}")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
