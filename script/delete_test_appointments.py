"""
Delete leftover Appointment + dependent rows tied to stress-test Patients
(phone +27795550% prefix). Used as a one-shot before re-running the
main cleanup_stress_test_patients.py script.
"""
import os
import psycopg2

with psycopg2.connect(os.environ["DATABASE_URL"]) as conn:
    with conn.cursor() as cur:
        # 1. Find appointments tied to stress-test patients.
        cur.execute("""
            SELECT a.id, p.phone, p.first_name, p.last_name, a.start_time, a.status
            FROM appointments a
            JOIN patients p ON p.id = a.patient_id
            WHERE p.phone LIKE '+27795550%'
        """)
        rows = cur.fetchall()
        if not rows:
            print("No appointments to delete. Exiting.")
            exit(0)

        print(f"Found {len(rows)} appointment(s) tied to stress-test patients:")
        for r in rows:
            print(f"  appt_id={r[0]}  phone={r[1]}  name={r[2]} {r[3]}  start={r[4]}  status={r[5]}")

        appt_ids = [r[0] for r in rows]

        # 2. Delete dependent rows first (audit trail kept for now in audit_logs).
        cur.execute("DELETE FROM cancellation_reasons WHERE appointment_id = ANY(%s)", (appt_ids,))
        print(f"Deleted {cur.rowcount} cancellation_reasons.")

        cur.execute("DELETE FROM confirmation_logs WHERE appointment_id = ANY(%s)", (appt_ids,))
        print(f"Deleted {cur.rowcount} confirmation_logs.")

        cur.execute("DELETE FROM notifications WHERE appointment_id = ANY(%s)", (appt_ids,))
        print(f"Deleted {cur.rowcount} notifications.")

        # 3. Delete the appointments themselves.
        cur.execute("DELETE FROM appointments WHERE id = ANY(%s)", (appt_ids,))
        print(f"Deleted {cur.rowcount} appointments.")

        conn.commit()
        print("Done.")
