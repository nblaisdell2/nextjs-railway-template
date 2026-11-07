import Link from "next/link";

export default function Home() {
  return (
    <main className="container">
      <div className="brand">
        <span className="dot" />
        Site Template
      </div>

      <h1>Ship a full-stack Next.js site on Railway.</h1>
      <p className="muted" style={{ maxWidth: 560 }}>
        A generic starting point for any project: a server-rendered Next.js app
        in a Docker container, talking to a managed PostgreSQL database, served
        over HTTPS. Push to <code>main</code> and Railway rebuilds and redeploys
        it for you.
      </p>

      <p style={{ marginTop: "1.5rem" }}>
        <Link className="btn" href="/demo">
          Open the database demo &rarr;
        </Link>
      </p>

      <div className="grid">
        <div className="card">
          <span className="pill">Frontend + API</span>
          <h3 style={{ margin: "0.6rem 0 0.3rem" }}>Next.js (App Router)</h3>
          <p className="muted" style={{ margin: 0 }}>
            Server components and route handlers, built as a standalone server
            image from the repo&apos;s Dockerfile.
          </p>
        </div>
        <div className="card">
          <span className="pill">Database</span>
          <h3 style={{ margin: "0.6rem 0 0.3rem" }}>Railway PostgreSQL</h3>
          <p className="muted" style={{ margin: 0 }}>
            Reached over Railway&apos;s private network. Migrations run
            automatically before every deploy.
          </p>
        </div>
        <div className="card">
          <span className="pill">Hosting</span>
          <h3 style={{ margin: "0.6rem 0 0.3rem" }}>Railway</h3>
          <p className="muted" style={{ margin: 0 }}>
            Deploys on every push, health-checks <code>/api/health</code>, and
            issues HTTPS certificates for your own domain.
          </p>
        </div>
      </div>

      <p className="muted" style={{ marginTop: "2rem", fontSize: "0.85rem" }}>
        Health endpoint: <Link href="/api/health">/api/health</Link>
      </p>
    </main>
  );
}
