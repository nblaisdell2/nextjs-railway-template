# CLAUDE.md

Guidance for AI coding assistants working in this repository. The person you're
helping may not be an experienced developer: explain what you're about to do in
plain language, prefer the npm scripts below over ad-hoc commands, and confirm
before anything that changes or deletes things on Railway.

## What this project is

A Next.js (App Router, TypeScript) site with a PostgreSQL database, hosted on
Railway. Project name: `nextjs-test`.

- `app/`: pages and API routes. `app/demo` + `app/api/notes` are a sample feature
  meant to be replaced. `app/api/health` is Railway's health check; keep it.
- `lib/db.ts`: the only way app code talks to Postgres. Use `query<T>(sql, params)`.
- `db/migrations/NNNN_name.sql`: the database schema, applied in filename order by
  `db/migrate.mjs`, which records each file in `schema_migrations`.
- `.railway/railway.ts`: Railway infrastructure-as-code (Postgres + `web` service).
- `Dockerfile`: how Railway builds and runs the app.
- `scripts/*.ps1` + `scripts/*.sh`: setup and Railway helpers (identical behavior).

## Commands

| Task | Command |
|------|---------|
| First-time local setup | `npm run setup` (needs a local Postgres; see README Quick start) |
| Run locally | `npm run dev`, then http://localhost:3000 |
| Check the code | `npm run lint` and `npm run build` (both must pass before pushing) |
| Apply migrations locally | `npm run migrate` |
| First deploy to Railway | `npm run railway:setup` |
| Deploy changes | commit and `git push` to `main` (Railway deploys automatically) |
| Deploy local folder now | `npm run railway:deploy` |
| Add a custom domain | `npm run railway:domain -- www.example.com` |
| Railway logs | `railway logs --service web` (add `--build` for build logs) |

## How to make common changes

**Add a page.** Create `app/<route>/page.tsx`. Pages that read the database must
`export const dynamic = "force-dynamic";` and call `query()` from `@/lib/db`
on the server. Interactive pieces go in a separate `"use client"` component
(see `app/demo/AddNoteForm.tsx`).

**Add an API route.** Create `app/api/<name>/route.ts` exporting `GET`/`POST`/...
with `export const dynamic = "force-dynamic"; export const runtime = "nodejs";`.
Validate input and always use parameterized SQL (`$1`, `$2`), never string concatenation.

**Change the database.** Add a NEW file `db/migrations/000N_description.sql`
(next number), then `npm run migrate`. Never edit or rename a migration that's
already been applied anywhere. Railway runs migrations before each deploy, and a
failing migration fails the deploy. Keep changes compatible with the currently
running code (add before use, remove after the code stops using it).

**Replace the demo.** Delete `app/demo`, `app/api/notes`, the demo link in
`app/page.tsx`, and add a migration that drops the `notes` table (don't delete
`0001_init.sql` once it's been applied on Railway).

**Change infrastructure** (env vars, replicas, health check, domains, new
services). Edit `.railway/railway.ts`, run `railway config plan`, show the person
the plan, and only then `railway config apply`. Pushing to GitHub does NOT apply
infra changes.

## Rules

- Never commit `.env` or any credential. Railway provides `DATABASE_URL` via a
  reference variable; don't hardcode connection strings anywhere.
- Never create a database pool at module top level; `next build` must work
  without `DATABASE_URL`. Use `lib/db.ts`.
- Never hardcode the port: Railway injects `PORT`.
- Keep `DATABASE_SSL=disable` for Railway's private network; `require` is only for
  the public TCP proxy (`DATABASE_PUBLIC_URL`).
- Removing a resource from `.railway/railway.ts` and applying DELETES it on
  Railway, including the Postgres database and its data. Never pass
  `--confirm-destructive` and never run `npm run railway:destroy` or
  `railway delete` without the person's explicit go-ahead.
- Don't add custom domains with `railway domain <d>` alone; use
  `npm run railway:domain -- <d>` so `.railway/railway.ts` stays the source of truth.
- When you change a script, change both the `.ps1` and the `.sh` version.
- Run `npm run lint` and `npm run build` before committing.
