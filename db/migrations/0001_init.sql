-- Minimal demo schema: a single table the demo page reads and writes.
-- Replace with your own app's schema.

CREATE TABLE IF NOT EXISTS notes (
  id          BIGSERIAL PRIMARY KEY,
  content     TEXT NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Seed a note so the UI isn't empty on first deploy.
INSERT INTO notes (content)
SELECT 'Hello from Postgres — this row was seeded by db/migrations/0001_init.sql.'
WHERE NOT EXISTS (SELECT 1 FROM notes);
