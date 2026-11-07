// Shared connection settings for the Node scripts in db/ (migrate,
// ensure-database). Mirrors lib/db.ts, which the app itself uses.
//
//   DATABASE_SSL=disable (default)  no TLS: local Postgres, Railway private network
//   DATABASE_SSL=require            TLS without cert verification: Railway's
//                                   public TCP proxy (DATABASE_PUBLIC_URL)

/** TLS option for pg, driven only by DATABASE_SSL. */
export function sslOption() {
  const mode = (process.env.DATABASE_SSL ?? "disable").toLowerCase();
  return mode === "require" ? { rejectUnauthorized: false } : false;
}

/**
 * Remove `sslmode` from a connection string so it can't override sslOption():
 * pg's URL parser would otherwise turn sslmode into its own TLS settings.
 */
export function stripSslmode(connStr) {
  try {
    const url = new URL(connStr);
    url.searchParams.delete("sslmode");
    return url.toString();
  } catch {
    return connStr;
  }
}
