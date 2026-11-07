// Minimal forward-only SQL migration runner.
//
//   npm run migrate        (= node --env-file-if-exists=.env db/migrate.mjs)
//
// Applies every .sql file in db/migrations (in filename order) that has not
// already been recorded in the schema_migrations table. Each file runs inside
// a transaction. Reads DATABASE_URL (and DATABASE_SSL) from the environment.
//
// On Railway this runs automatically as the web service's pre-deploy command
// (see .railway/railway.ts): a failing migration fails the deploy, so the new
// version never serves traffic against a half-migrated schema.

import { readdir, readFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import pg from "pg";
import { sslOption, stripSslmode } from "./connection.mjs";

const __dirname = dirname(fileURLToPath(import.meta.url));
const migrationsDir = join(__dirname, "migrations");

const connectionString = process.env.DATABASE_URL;
if (!connectionString) {
  console.error(
    "ERROR: DATABASE_URL is not set. Locally, run `npm run setup` (or create .env from .env.example)."
  );
  process.exit(1);
}

const client = new pg.Client({
  connectionString: stripSslmode(connectionString),
  ssl: sslOption(),
});

async function main() {
  await client.connect();

  await client.query(`
    CREATE TABLE IF NOT EXISTS schema_migrations (
      filename   TEXT PRIMARY KEY,
      applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
    )
  `);

  const applied = new Set(
    (await client.query("SELECT filename FROM schema_migrations")).rows.map(
      (r) => r.filename
    )
  );

  const files = (await readdir(migrationsDir))
    .filter((f) => f.endsWith(".sql"))
    .sort();

  let count = 0;
  for (const file of files) {
    if (applied.has(file)) {
      console.log(`= skip   ${file}`);
      continue;
    }
    const sql = await readFile(join(migrationsDir, file), "utf8");
    console.log(`+ apply  ${file}`);
    try {
      await client.query("BEGIN");
      await client.query(sql);
      await client.query(
        "INSERT INTO schema_migrations (filename) VALUES ($1)",
        [file]
      );
      await client.query("COMMIT");
      count++;
    } catch (err) {
      await client.query("ROLLBACK");
      console.error(`\nFailed on ${file}:\n`, err.message);
      process.exitCode = 1;
      return;
    }
  }

  console.log(`\nDone. ${count} migration(s) applied.`);
}

main()
  .catch((err) => {
    console.error(err);
    process.exitCode = 1;
  })
  .finally(() => client.end());
