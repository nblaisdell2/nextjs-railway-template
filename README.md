# Next.js + Railway Site Template

A starting point for any server-rendered **Next.js** (App Router) site with a
**PostgreSQL** database, hosted on **[Railway](https://railway.com)**. The whole
loop is: *use the template → one setup command → one deploy command → push to
`main`*. You end up with a live site on HTTPS, optionally on your own domain.

The included pages are a small demo (a list of notes stored in Postgres) that
proves the wiring end to end. Replace them with your own app.

```
git push origin main ──> Railway (GitHub integration)
                           ├─ builds the Dockerfile
                           ├─ pre-deploy: npm run migrate   (fails the deploy if a migration fails)
                           ├─ starts the container, waits for /api/health = 200
                           └─ switches traffic to the new version

Browser ──HTTPS──> web service (*.up.railway.app or your domain, cert by Let's Encrypt)
                     │  DATABASE_URL = ${{postgres.DATABASE_URL}}  (reference variable)
                     ▼  private network only, no TLS needed
                   postgres service (Railway-managed PostgreSQL + volume, not exposed publicly)
```

**New to building sites?** You can do everything below by asking an AI coding
assistant such as [Claude Code](https://claude.com/claude-code) to do it for you.
See [Working with an AI assistant](#working-with-an-ai-assistant).

## Quick start

**Prerequisites:** Node.js 22+, Docker (for the local database), the
[GitHub CLI](https://cli.github.com/) (`gh auth login`), the
[Railway CLI](https://docs.railway.com/cli) (`npm install -g @railway/cli`, then
`railway login`), and PowerShell 7 (`pwsh`) for the npm aliases. On macOS/Linux
without `pwsh`, run the matching `scripts/*.sh` directly (see [Scripts](#scripts)).

```bash
# 1. Create your repo from this template and clone it. Either use GitHub's
#    "Use this template" button, then clone it, or in one line:
gh repo create my-new-app --template nblaisdell2/nextjs-railway-template --private --clone
cd my-new-app

# 2. Start a local Postgres (skip if you already have one; flags explained below):
docker run --name pg -e POSTGRES_PASSWORD=postgres -p 5432:5432 -d postgres:16

# 3. Onboard: npm install, write .env, create the local DB, migrate, and
#    personalize the project (name + GitHub repo, taken from the folder name).
npm run setup            # prompts for the local Postgres password ("postgres" above)

# 4. Run it locally:
npm run dev              # http://localhost:3000

# 5. Commit the personalized files and push:
git add -A && git commit -m "Personalize template" && git push -u origin main

# 6. Deploy to Railway (creates the project, database and web service; prints the live URL):
npm run railway:setup
```

From then on, **every push to `main` deploys**.

What the `docker run` flags mean:

| Flag | Meaning |
|------|---------|
| `--name pg` | Names the container `pg`, so you can `docker stop pg` / `docker start pg` later |
| `-e POSTGRES_PASSWORD=postgres` | Sets the database superuser's password (this is what `npm run setup` asks for) |
| `-p 5432:5432` | Exposes Postgres on `localhost:5432`. If that port is already taken (for example by a Postgres you installed), use `-p 5433:5432` and run `npm run setup -- -DbPort 5433` |
| `-d` | Runs it in the background |
| `postgres:16` | The official PostgreSQL 16 image |

## What's here

| Path | Purpose |
|------|---------|
| `app/` | Next.js App Router: landing page, `demo/` (the notes demo page), `api/notes` (its API), and `api/health` (health check used by Railway) |
| `lib/db.ts` | Shared `pg` connection pool, created lazily; TLS controlled by `DATABASE_SSL` |
| `db/migrations/*.sql` | Your database schema, as numbered SQL files applied in order |
| `db/migrate.mjs` | Forward-only migration runner (records applied files in `schema_migrations`) |
| `db/ensure-database.mjs` | Creates the local database if it's missing (local dev only) |
| `.railway/railway.ts` | **Railway infrastructure-as-code**: the Postgres service, the web service, its settings, and domains |
| `Dockerfile` | Multi-stage build of the standalone Next.js server; runs as a non-root user and listens on `PORT` |
| `scripts/` | Setup and Railway helper scripts, each in PowerShell (`.ps1`) and Bash (`.sh`) |
| `.env.example` | Template for your local `.env` (`DATABASE_URL`, `DATABASE_SSL`) |
| `CLAUDE.md` | Instructions for AI coding assistants working in this repo |

## Scripts

Every script ships in both PowerShell (`.ps1`) and Bash (`.sh`) and behaves the
same in both. The npm aliases call the PowerShell version through `pwsh`, so
they work on any OS that has PowerShell 7.

| npm | Script | What it does |
|-----|--------|--------------|
| `npm run dev` / `build` / `start` / `lint` | Next.js | Develop, build, run, lint |
| `npm run migrate` | `db/migrate.mjs` | Apply pending migrations to whatever `DATABASE_URL` points at (reads `.env`) |
| `npm run db:ensure` | `db/ensure-database.mjs` | Create the local database if it doesn't exist |
| `npm run setup` | `setup-local` | One-shot local onboarding (below) |
| `npm run template:init` | `init-from-template` | One-time, offline personalization (below) |
| `npm run railway:setup` | `setup-railway` | First-time deploy, end to end (below) |
| `npm run railway:deploy` | `railway-deploy` | Deploy your local folder now, without waiting for a push |
| `npm run railway:migrate` | `railway-migrate` | Re-run migrations against the live database without pushing |
| `npm run railway:domain` | `railway-domain` | Generate the Railway domain, or attach a custom domain |
| `npm run railway:destroy` | `railway-destroy` | Delete the Railway project (asks you to type its name) |

Pass arguments after `--`, e.g. `npm run template:init -- -ProjectName my-app -GitHubRepo me/my-app`.
The Bash versions take `--flag value` style arguments (shown below).

**`setup`** (`-DbPassword`, `-DbName test`, `-DbPort 5432` / `--password=`, `--db-name=`, `--db-port=`)
1. Asks for the local Postgres password (hidden input).
2. `npm install`.
3. Writes `.env` from `.env.example` with a URL-encoded password and `DATABASE_SSL=disable`.
4. `npm run db:ensure`, then `npm run migrate`.
5. Runs `template:init` with the folder name as the project name and `<your GitHub login>/<folder>` as the repo.

**`template:init`** (`-ProjectName`, `-GitHubRepo`, `-CustomDomain` / `--name`, `--repo`, `--custom-domain`)
Offline: it only edits files, so you can review it with `git diff` before
anything exists on Railway. It swaps the template's placeholder name for your
project name (`.railway/railway.ts`, `package.json`, `package-lock.json`,
`README.md`, `CLAUDE.md`), writes your GitHub `owner/repo` into
`.railway/railway.ts`, and optionally records a custom domain (`CUSTOM_DOMAIN`)
that `railway:setup` attaches. Project names are 3–30 lowercase letters, digits
or hyphens, starting with a letter.

**`railway:setup`** (`-Yes` / `--yes`). Safe to re-run.
1. Checks prerequisites: Railway CLI and login (offers `railway login`), `gh auth status`, a git `origin` remote, and that `railway.ts` has been personalized.
2. Links this folder to the Railway project named in `railway.ts` (`railway link`); if it doesn't exist, asks before creating it (`railway init`). Without a terminal it never creates a project unless you pass `-Yes`.
3. `railway config plan` (always shown), then `railway config apply` (asks you to confirm). This creates Postgres and the web service; connecting the GitHub repo starts the first deploy.
4. If nothing is pushed to `main` yet, prints the `git push` command and stops. Otherwise waits for that deploy to finish.
5. Generates the `*.up.railway.app` domain if the service has none, and attaches `CUSTOM_DOMAIN` if one is set.
6. Prints the live HTTPS URL and, for a custom domain, the DNS records to add.

`-Yes` creates the project without asking and passes `--yes` to `railway config apply`.
Destructive changes (deleting a service, variable or volume) are never confirmed automatically.

**`railway:deploy`**: `railway up --service web --ci`. Uploads your local folder
(respecting `.gitignore`, uncommitted changes included), builds it on Railway
and prints the URL. Handy for a quick check; the next push to `main` replaces it.

**`railway:migrate`** (`-Ssh` / `--ssh`): you rarely need it, because every
deploy already migrates. By default it runs `railway redeploy` on the web
service, which re-runs the pre-deploy `npm run migrate` with Railway's
`DATABASE_URL` (never your local `.env`), waits for it, and prints the
migration output. With `-Ssh` it instead runs `npm run migrate` inside the
running container over `railway ssh` (no restart), which needs an SSH key on
your machine (`ssh-keygen -t ed25519`). Either way it runs the migrations in the
*deployed* image, so push new migration files first.

**`railway:domain [domain]`**: see [Custom domain](#custom-domain).

**`railway:destroy`** (`-Yes` / `--yes`): shows what will be deleted, reminds you
to dump the data first, asks you to type the project name, then runs
`railway delete` and unlinks the folder.

## Local development

`npm run setup` does all of this. By hand, or day to day:

```bash
npm install
docker start pg             # or the docker run command from Quick start
cp .env.example .env        # then set the password + database name in DATABASE_URL
npm run db:ensure           # create the database if it doesn't exist
npm run migrate             # apply migrations
npm run dev                 # http://localhost:3000
```

### Changing the database

Add a new file in `db/migrations/` with the next number, e.g.
`0002_add_tags.sql`, then run `npm run migrate`. Never edit a migration that has
already been applied (locally or on Railway). Write a new one instead. When you
push, Railway applies it before the new code takes traffic.

## Deploying

### Deployment model

| What changes | Who applies it | How |
|--------------|----------------|-----|
| **Code** (pages, APIs, migrations) | GitHub → Railway | `git push` to `main`. Railway builds the Dockerfile, migrates, health-checks, swaps traffic. Railway serializes deploys itself. |
| **Infrastructure** (services, variables, health check, replicas) | Your laptop | Edit `.railway/railway.ts`, then `railway config plan` and `railway config apply` |
| **Domains** | Your laptop | `npm run railway:domain [domain]` (uses `railway domain`; Railway's IaC can't create domains) |
| **Secrets / credentials** | Railway | Postgres credentials are generated by Railway and referenced by name; nothing sensitive is in git or in the image |
| **Quick manual deploy** | Your laptop | `npm run railway:deploy` |

Your laptop owns `railway.ts`, and pushes own code rollouts: the same split as a
Terraform + CI setup, without any IAM roles to enforce it. There is no GitHub
Actions workflow and no deploy secret to set; Railway's GitHub integration
handles deploy-on-push.

### What `.railway/railway.ts` declares

- `postgres("postgres")`: a managed PostgreSQL service with its own volume,
  reachable only over the private network (`postgres.railway.internal`).
- `service("web")`, which:
  - deploys from your GitHub repo's `main` branch
  - is built from the `Dockerfile`
  - runs `npm run migrate` as its pre-deploy command
  - waits for `/api/health` to return 200 (120 s timeout)
  - runs 1 replica, with Railway's default restart policy (on failure, up to 10 times)
  - gets `DATABASE_URL` as a reference to `postgres.DATABASE_URL`, plus `DATABASE_SSL=disable` and `NODE_ENV=production`
- `project("<your project>")` containing both.

It also holds `PROJECT_NAME`, `GITHUB_REPO` and `CUSTOM_DOMAIN`, which the npm
scripts read. Domains themselves are attached by the scripts, not declared in
`service()`, because Railway's IaC can't register custom domains.
Railway injects `PORT` into the web container; the Next.js server listens on it.

### Logs and status

```bash
railway logs --service web            # runtime logs (including pre-deploy migrations)
railway logs --service web --build    # build logs
railway status                        # what's linked
railway open                          # the project in the dashboard
```

The dashboard shows the same logs plus metrics per deployment.

### Scaling

Set `replicas` in `.railway/railway.ts` (e.g. `replicas: 2`) and run
`railway config apply`. Or run `railway scale --service web us-east=2`; if you do
that, put the same number in `railway.ts` so the next apply doesn't undo it.
Remember each replica opens its own database pool (`DATABASE_POOL_MAX`, default 5).

## Custom domain

1. Attach the domain:
   ```bash
   npm run railway:domain -- app.example.com
   ```
   This runs `railway domain app.example.com --service web`, prints the DNS
   records from `railway domain status`, and records
   `CUSTOM_DOMAIN = "app.example.com"` in `.railway/railway.ts` (commit it).
   You can also set it from the start with
   `npm run template:init -- -ProjectName my-app -CustomDomain app.example.com`;
   `railway:setup` then attaches it after the first deploy.
2. At your DNS provider, add **both** records shown:
   - a **CNAME** from your domain to the Railway target (routes the traffic), and
   - a **TXT** record (proves you own the domain). Without the TXT, Railway answers **404** even when the CNAME resolves.
3. Wait for DNS to propagate. Railway issues the Let's Encrypt certificate
   automatically; there's nothing to upload. Check progress with:
   ```bash
   railway domain status app.example.com --service web
   ```

**Cloudflare:** never proxy `_acme-challenge` records. Nested subdomains
(`a.b.example.com`) must be **DNS only** (grey cloud) unless you pay for
Cloudflare's Advanced Certificate Manager, because Cloudflare's universal
certificate only covers one level of subdomain. A root domain needs CNAME
flattening (Cloudflare does this automatically for the apex).

Without an argument, `npm run railway:domain` generates the free
`*.up.railway.app` domain (if the service doesn't have one yet). The generated
domain keeps working alongside your custom one.

Switching domains: running `railway:domain` with a new domain attaches it and
updates `CUSTOM_DOMAIN`, but leaves the old one attached; it prints the
`railway domain delete <old> --service web --yes` command to remove it.

## Cost and teardown

Railway bills by usage: CPU, memory, Postgres volume storage and network egress
for both services. See [railway.com/pricing](https://railway.com/pricing) and
check your current spend with `railway usage`.

**Backups.** The Postgres data lives on a Railway volume. Take an on-demand
backup, or set a schedule, with:

```bash
railway postgres pitr backup create --service postgres   # one-off backup
railway postgres pitr schedule set --service postgres    # daily / weekly / monthly
railway postgres pitr enable --service postgres          # continuous point-in-time recovery
```

The same controls are on the Postgres service's **Backups** tab in the dashboard.
Backups belong to the project, so **deleting the project deletes them too.**

**Reaching the database from your laptop** (for `pg_dump`, a GUI client, or a
one-off query). The database has no public address by default. Either:

- `railway connect postgres`: opens `psql` through an SSH tunnel (needs `psql`
  and an SSH key on your machine), or
- open a temporary public TCP proxy, use it, then close it:
  ```bash
  railway tcp-proxy create --port 5432 --service postgres
  railway variables --service postgres   # PGUSER, PGPASSWORD, PGDATABASE,
                                         # RAILWAY_TCP_PROXY_DOMAIN, RAILWAY_TCP_PROXY_PORT
  pg_dump "postgresql://PGUSER:PGPASSWORD@PROXY_DOMAIN:PROXY_PORT/PGDATABASE?sslmode=require" > backup.sql
  railway tcp-proxy list --service postgres  # get the proxy id, then:
  railway tcp-proxy delete <id> --service postgres --yes
  ```
  (Substitute the values; URL-encode the password if it has special characters.)
  If you point this app or `npm run migrate` at that URL, set `DATABASE_SSL=require`.

Dump anything you want to keep before tearing down.

**Tear down everything:**

```bash
npm run railway:destroy
```

It lists what will be deleted, asks you to type the project name, and runs
`railway delete`. The site goes offline immediately and Railway purges the
project after a grace period (about 48 hours). Your GitHub repo and local files
are untouched; run
`npm run railway:setup` again to start fresh.

## Using as a template for new projects

This repo is a GitHub **template repository**. For a new project:

1. "Use this template" (or `gh repo create my-new-app --template nblaisdell2/nextjs-railway-template --private --clone`).
2. `npm run setup`. It personalizes the project from the folder name and your GitHub login, then sets up local dev.
   - To *only* personalize: `npm run template:init -- -ProjectName my-app -GitHubRepo owner/my-app`.
3. Review `git diff`, commit, push to `main`.
4. `npm run railway:setup`.
5. Build your app: replace `app/demo`, `app/api/notes` and `db/migrations/0001_init.sql`
   with your own pages, APIs and migrations. `lib/db.ts`, `app/api/health`, `db/migrate.mjs`,
   the `Dockerfile` and `.railway/railway.ts` are app-agnostic and can stay as they are.

## Working with an AI assistant

`CLAUDE.md` tells AI coding assistants (Claude Code and others that read it) how this
project fits together, what's safe to change, and which commands to run. Open the
project folder in [Claude Code](https://claude.com/claude-code) and ask in plain
English, for example:

- "Set this project up for local development and start it."
- "Add a page at /about with a short bio and link it from the home page."
- "Add a `tags` table with a migration and show tags on the demo page."
- "Deploy this to Railway." / "Why did my last Railway deploy fail?"
- "Put the site on www.example.com."

The assistant runs the same npm scripts documented here. Commands that change
Railway (`railway config apply`, `railway:destroy`) ask for confirmation, and so
should you: read what they print before saying yes.

## Design decisions and gotchas

- **`PORT` is injected by Railway.** Never hardcode `3000` in the server. The
  Dockerfile's `PORT=3000` is only the fallback for a plain `docker run`, and
  Next's standalone `server.js` reads `PORT` and `HOSTNAME=0.0.0.0`.
- **The private network doesn't need TLS, so `DATABASE_SSL=disable` is correct there.**
  `postgres.railway.internal` is only reachable from inside your project, and the
  database has no public address unless you open a TCP proxy. Use
  `DATABASE_SSL=require` when connecting through such a proxy: the proxy also
  accepts unencrypted connections, so `require` is what keeps traffic across the
  internet encrypted. Its certificate is self-signed, so `require` encrypts
  without verifying it.
- **`sslmode` in the URL is stripped on purpose.** `pg` turns `?sslmode=...` into
  its own TLS settings (newer versions treat `sslmode=require` as full
  verification), which would silently override `DATABASE_SSL`. One switch, no surprises.
- **Pre-deploy migrations gate the release.** If a migration fails, the deploy
  fails and the previous version keeps serving, rather than serving new code
  against a half-migrated schema. Keep migrations backward compatible with the
  version that's still running (add columns before using them, drop them later).
- **`next build` must not touch the database.** `lib/db.ts` creates its pool on
  first query, so builds (locally and on Railway) don't need `DATABASE_URL`.
  Pages that query the database use `export const dynamic = "force-dynamic"`.
- **Node doesn't load `.env` by itself.** The npm scripts use
  `node --env-file-if-exists=.env`; inside the container there's no `.env`, and
  Node prints a harmless "not found" note before using Railway's variables.
- **PowerShell and flags containing `=`.** Quote them: `"--flag=value"`. Unquoted,
  PowerShell can split the argument before the CLI sees it. The PowerShell
  scripts avoid `=` flags for this reason.
- **Custom domains need both CNAME and TXT**, and Cloudflare proxying has limits
  (see [Custom domain](#custom-domain)).
- **Railway does not read `.railway/` during deploys.** A push ships code only;
  `railway config apply` is the only way infrastructure changes land.
- **`railway.ts` is the whole truth for services and variables.** Removing a
  resource from it and applying **deletes** it on Railway, including the Postgres
  database. The plan marks these as destructive and asks again; read it.
- **Railway's IaC can't create custom domains.** Declaring one in `service({ domains })`
  fails the plan with "Custom-domain registration is not supported" until the
  domain already exists, so this template attaches domains with `railway domain`
  (via `npm run railway:domain`) and keeps `CUSTOM_DOMAIN` as a plain setting.
  Domains not declared in the file are left alone by `railway config apply`.
- **Don't declare settings that equal Railway's defaults.** Railway stores a
  default as "unset", so e.g. `restartPolicyType: "ON_FAILURE"` shows up as a
  change, and triggers a redeploy, on every `railway config apply`. If
  `railway config plan` keeps showing the same change, that's why.
- **`RAILWAY_PUBLIC_DOMAIN` switches to your custom domain** once one exists. The
  scripts read the generated domain from `railway domain list` instead.
- **`railway run` executes on your laptop.** It injects Railway's variables, but
  `postgres.railway.internal` doesn't resolve outside Railway, so
  `railway run npm run migrate` can't reach the database. `railway:migrate`
  redeploys (or uses `railway ssh` with `-Ssh`) instead.
- **Windows: `railway config` needs a workaround with an npm-installed CLI.** The
  `railway/iac` package checks the CLI version by spawning `railway` without a
  shell, which can't run npm's `railway.cmd` shim, so `railway config plan` fails
  with "requires Railway CLI 5.42.1 or newer" even on a newer CLI. The scripts
  work around it (`Invoke-RailwayConfig` / `railway_config` in `scripts/lib/`).
  Running `railway config ...` by hand on Windows: in PowerShell, first run
  `$env:_ = "$(npm root -g)\@railway\cli\bin\railway.exe"`, or install the CLI
  with a native installer (e.g. `scoop install railway`) instead of npm.

## Manual steps in the Railway dashboard

Normally none: `railway:setup` does everything from the CLI. Check these if it stops:

- **Plan / billing:** creating a project needs an active plan. If `railway init`
  fails with "Your trial has expired", pick a plan in the dashboard and re-run.
- **GitHub access:** Railway's GitHub app must be able to see your repo for
  deploy-on-push. If `railway:setup` reports that no deploy started, open the
  project (`railway open`) → web → Settings → Source, connect the repo (granting
  the Railway app access when GitHub asks), then re-run `npm run railway:setup`.
- **Optional:** backup schedules, usage limits and alerts are easiest to set in
  the dashboard (`railway open`).
