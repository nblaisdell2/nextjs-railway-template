// Pick this project's local database name and print it to stdout. LOCAL DEV
// ONLY; `npm run setup` calls it when you don't pass a name yourself.
//
//   1. .env already names a database -> reuse it, so re-running setup never
//      creates another one.
//   2. Otherwise use the project folder's name (my-new-app -> my_new_app).
//   3. If that's already taken on this Postgres server, add a random suffix
//      (my_new_app_3fa9), so two projects never share a database by accident.
//
// Connects with SETUP_ADMIN_URL (the server's "postgres" maintenance database).
// It's deliberately not DATABASE_URL: Node's --env-file doesn't override
// variables that are already set, so a leftover DATABASE_URL would hijack the
// `db:ensure` and `migrate` steps that follow.
//
// Only the name goes to stdout, because the setup scripts capture it. Notes and
// errors go to stderr.

import { randomBytes } from "node:crypto";
import { readFile } from "node:fs/promises";
import { basename, dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import pg from "pg";
import { sslOption, stripSslmode } from "./connection.mjs";

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const VALID_NAME = /^[A-Za-z_][A-Za-z0-9_]*$/;

/** The database already named in .env, or null. */
async function nameFromEnvFile() {
  let text;
  try {
    text = await readFile(join(root, ".env"), "utf8");
  } catch {
    return null;
  }
  const match = text.match(/^DATABASE_URL=(.+)$/m);
  if (!match) return null;
  try {
    const name = decodeURIComponent(new URL(match[1].trim()).pathname.slice(1));
    return VALID_NAME.test(name) && name !== "postgres" ? name : null;
  } catch {
    return null;
  }
}

/** The project folder's name, as a valid database name. */
function nameFromFolder() {
  let name = basename(root)
    .toLowerCase()
    .replace(/[^a-z0-9_]+/g, "_")
    .replace(/^_+|_+$/g, "");
  if (!/^[a-z]/.test(name)) name = name ? `db_${name}` : "app";
  // Postgres allows 63 characters; leave room for the random suffix.
  return name.slice(0, 50);
}

async function main() {
  const existing = await nameFromEnvFile();
  if (existing) {
    console.error(`Reusing database "${existing}" from .env.`);
    return existing;
  }

  const adminUrl = process.env.SETUP_ADMIN_URL;
  if (!adminUrl) throw new Error("SETUP_ADMIN_URL is not set.");

  const client = new pg.Client({
    connectionString: stripSslmode(adminUrl),
    ssl: sslOption(),
  });
  await client.connect();
  try {
    const exists = async (candidate) =>
      (
        await client.query("SELECT 1 FROM pg_database WHERE datname = $1", [
          candidate,
        ])
      ).rowCount > 0;

    const base = nameFromFolder();
    if (!(await exists(base))) return base;

    let name;
    do {
      name = `${base}_${randomBytes(2).toString("hex")}`;
    } while (await exists(name));
    console.error(
      `Database "${base}" already exists on this server, so this project will use "${name}".`
    );
    return name;
  } finally {
    await client.end().catch(() => {});
  }
}

main()
  .then((name) => process.stdout.write(`${name}\n`))
  .catch((err) => {
    // Connection failures can arrive with an empty message and only a code.
    console.error(`Could not choose a database name: ${err.message || err.code}`);
    process.exitCode = 1;
  });
