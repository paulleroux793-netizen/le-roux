"""
One-shot cleanup script — removes Patient + Conversation rows created by
the 2026-05-06 stress test (phone numbers +27795550101 through +27795550117).

Run via:
    railway run --service le-roux python script/cleanup_stress_test_patients.py

Safety:
  - Verifies zero Appointments tied to those Patients before deleting (refuses
    to run if any appointments exist — that would suggest real data accidentally
    matched the pattern).
  - Reports counts before + after.
  - Does not touch any other rows.
"""
import os
import sys
import psycopg2

PHONE_PREFIX = "+27795550"  # matches +27795550101 through +27795550117 (and v2 +27795550201-208)


def main():
    db_url = os.environ.get("DATABASE_URL")
    if not db_url:
        print("ERROR: DATABASE_URL not set (run via `railway run`)", file=sys.stderr)
        sys.exit(2)

    with psycopg2.connect(db_url) as conn:
        with conn.cursor() as cur:
            # 1. Count what we're about to delete.
            cur.execute(
                "SELECT id, phone, first_name, last_name, created_at FROM patients "
                "WHERE phone LIKE %s ORDER BY phone",
                (PHONE_PREFIX + "%",),
            )
            rows = cur.fetchall()
            print(f"Found {len(rows)} stress-test Patient rows:")
            for r in rows:
                print(f"  id={r[0]}  phone={r[1]}  name={r[2]} {r[3]}  created={r[4]}")

            if not rows:
                print("Nothing to clean up. Exiting.")
                return

            # 2. Safety: confirm zero Appointments tied to these Patients.
            patient_ids = [r[0] for r in rows]
            cur.execute(
                "SELECT COUNT(*) FROM appointments WHERE patient_id = ANY(%s)",
                (patient_ids,),
            )
            appt_count = cur.fetchone()[0]
            if appt_count > 0:
                print(f"\n⚠️  ABORT: {appt_count} appointments are tied to these Patients.")
                print("    Real data may have accidentally matched the +27795550 prefix.")
                print("    Refusing to delete. Inspect manually before re-running.")
                sys.exit(3)

            # 3. Delete conversations first (FK to patients).
            cur.execute(
                "DELETE FROM conversations WHERE patient_id = ANY(%s) RETURNING id",
                (patient_ids,),
            )
            deleted_convos = cur.rowcount
            print(f"\nDeleted {deleted_convos} conversations.")

            # 4. Delete patients.
            cur.execute(
                "DELETE FROM patients WHERE id = ANY(%s) RETURNING id",
                (patient_ids,),
            )
            deleted_patients = cur.rowcount
            print(f"Deleted {deleted_patients} patients.")

            conn.commit()
            print("\n✅ Cleanup complete.")


if __name__ == "__main__":
    main()
