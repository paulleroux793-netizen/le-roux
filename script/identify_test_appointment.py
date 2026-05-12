"""Find the test-prefix patient who has an appointment, so we can decide what to do."""
import os
import psycopg2
import psycopg2.extras

with psycopg2.connect(os.environ["DATABASE_URL"]) as conn:
    with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
        cur.execute("""
            SELECT a.id AS appt_id, a.start_time, a.end_time, a.status, a.reason, a.notes,
                   p.id AS patient_id, p.phone, p.first_name, p.last_name, p.created_at
            FROM appointments a
            JOIN patients p ON p.id = a.patient_id
            WHERE p.phone LIKE '+27795550%'
            ORDER BY a.start_time
        """)
        for row in cur.fetchall():
            print(row)
