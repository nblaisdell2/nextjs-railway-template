import { Pool, type QueryResultRow } from "pg";

/**
 * A single shared connection pool for the whole app, created lazily on first
 * use. Lazy creation matters: Next.js imports route modules at build time to
 * collect metadata, and we must not require DATABASE_URL just to import this
 * file — only when a query actually runs.
 *
 * In development, Next.js hot-reloads modules, which would otherwise create a
 * new Pool on every reload and exhaust connections, so we stash it on the
 * Node global to survive reloads.
 *
 * Connection config comes entirely from environment variables:
 *   DATABASE_URL  locally: from .env (written by `npm run setup`)
 *                 on Railway: a reference to the Postgres service's
 *                 DATABASE_URL, declared in .railway/railway.ts
 *   DATABASE_SSL  "disable" (default) or "require" — see buildSsl() below
 */

declare global {
  var _pgPool: Pool | undefined;
}

/**
 * Remove the `sslmode` query param from a connection string. pg's
 * connection-string parser turns sslmode into its own TLS settings (recent
 * versions treat sslmode=require as full certificate verification), which
 * would silently override the decision made in buildSsl(). DATABASE_SSL is
 * the single switch, so sslmode is stripped.
 */
function stripSslmode(connectionString: string): string {
  try {
    const url = new URL(connectionString);
    url.searchParams.delete("sslmode");
    return url.toString();
  } catch {
    return connectionString;
  }
}

/**
 * Decide TLS behaviour from DATABASE_SSL:
 *  - "disable" (or unset) -> no TLS. Correct for a local Postgres and for
 *    Railway's private network (postgres.railway.internal), which is already
 *    isolated to your project and does not speak TLS.
 *  - "require" -> encrypted, certificate not verified. Use this only when
 *    connecting through Railway's public TCP proxy (DATABASE_PUBLIC_URL),
 *    whose certificate is self-signed.
 */
function buildSsl(): false | { rejectUnauthorized: false } {
  const mode = (process.env.DATABASE_SSL ?? "disable").toLowerCase();
  if (mode === "require") return { rejectUnauthorized: false };
  if (mode !== "disable") {
    console.warn(
      `[db] Unknown DATABASE_SSL="${process.env.DATABASE_SSL}"; expected "disable" or "require". Using "disable".`
    );
  }
  return false;
}

function createPool(): Pool {
  const raw = process.env.DATABASE_URL;
  if (!raw) {
    throw new Error(
      "DATABASE_URL is not set. Locally, run `npm run setup` (or copy .env.example to .env). " +
        "On Railway it is injected from the Postgres service (see .railway/railway.ts)."
    );
  }

  return new Pool({
    connectionString: stripSslmode(raw),
    ssl: buildSsl(),
    max: Number(process.env.DATABASE_POOL_MAX ?? 5),
    idleTimeoutMillis: 30_000,
    connectionTimeoutMillis: 10_000,
  });
}

/** Returns the shared pool, creating it on first call. */
export function getPool(): Pool {
  if (!global._pgPool) {
    global._pgPool = createPool();
  }
  return global._pgPool;
}

/** Typed query helper. */
export async function query<T extends QueryResultRow = QueryResultRow>(
  text: string,
  params?: unknown[]
): Promise<T[]> {
  const res = await getPool().query<T>(text, params as never[]);
  return res.rows;
}
