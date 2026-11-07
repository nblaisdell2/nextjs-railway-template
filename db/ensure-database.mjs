// Ensure the target database exists, creating it if missing. LOCAL DEV ONLY —
// Railway's Postgres service creates its own database.
//
//   npm run db:ensure      (= node --env-file-if-exists=.env db/ensure-database.mjs)
//
// Postgres has no "CREATE DATABASE IF NOT EXISTS", so we connect to the server's
// "postgres" maintenance database, check pg_database, and create the target if
// it's absent. The target + credentials are read from DATABASE_URL.

import pg from "pg";
import { sslOption, stripSslmode } from "./connection.mjs";

const raw = process.env.DATABASE_URL;
if (!raw) {
  console.error("DATABASE_URL is not set.");
  process.exit(1);
}

// Target DB name = the path of DATABASE_URL (e.g. .../test -> "test").
const targetUrl = new URL(raw);
const target = decodeURIComponent(targetUrl.pathname.replace(/^\//, "")) || "postgres";

// Identifier safety: we can't parameterize a CREATE DATABASE name, so validate it.
if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(target)) {
  console.error(`Refusing to create a database with an unusual name: "${target}".`);
  process.exit(1);
}

if (target === "postgres") {
  console.log('Target database is "postgres"; nothing to create.');
  process.exit(0);
}

// Connect to the same server but the "postgres" maintenance DB.
const adminUrl = new URL(raw);
adminUrl.pathname = "/postgres";

const client = new pg.Client({
  connectionString: stripSslmode(adminUrl.toString()),
  ssl: sslOption(),
});

try {
  await client.connect();
  const { rowCount } = await client.query(
    "SELECT 1 FROM pg_database WHERE datname = $1",
    [target]
  );
  if (rowCount === 0) {
    await client.query(`CREATE DATABASE "${target}"`);
    console.log(`Created database "${target}".`);
  } else {
    console.log(`Database "${target}" already exists.`);
  }
} catch (err) {
  console.error(`Failed to ensure database "${target}": ${err.message}`);
  process.exitCode = 1;
} finally {
  await client.end().catch(() => {});
}
