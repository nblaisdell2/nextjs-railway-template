// Railway infrastructure-as-code: the single declarative description of this
// project's hosting stack. It plays the role Terraform used to play.
//
//   railway config plan     preview what would change (always look first)
//   railway config apply    make Railway match this file
//
// `npm run railway:setup` runs both for you the first time. After that, edit
// this file and run them yourself whenever the INFRASTRUCTURE changes. Code
// changes don't need it: every push to `main` rebuilds and redeploys `web`.
//
// Railway does not read this folder during deploys. A push never changes
// infrastructure, only `railway config apply` does.
//
// WARNING: this file is the whole truth. Removing a resource here and applying
// DELETES it on Railway, and that includes the Postgres database and its data.
//
// Reference: https://docs.railway.com/infrastructure-as-code/reference

import { defineRailway, github, postgres, project, service } from "railway/iac";

// ---- Project identity (filled in by `npm run template:init`) ---------------
const PROJECT_NAME = "nextjs-test";
const GITHUB_REPO = "OWNER/nextjs-test";
// Optional custom domain, e.g. "app.example.com". Leave "" to use only the
// generated *.up.railway.app domain. See "Custom domain" in the README.
const CUSTOM_DOMAIN = "";
// ----------------------------------------------------------------------------

export default defineRailway(() => {
  // Managed PostgreSQL. Railway generates the credentials and exposes them as
  // variables on this service (DATABASE_URL, DATABASE_PUBLIC_URL, PG*).
  const db = postgres("postgres");

  const web = service("web", {
    // Deploy-on-push: Railway watches this repo/branch and redeploys on push.
    source: github(GITHUB_REPO, { branch: "main" }),

    // Build the repo's Dockerfile (multi-stage, standalone Next.js server).
    build: { builder: "DOCKERFILE", dockerfilePath: "Dockerfile" },

    deploy: {
      // Apply pending SQL migrations before the new version takes traffic.
      // A failing migration fails the deploy; the old version keeps serving.
      preDeployCommand: ["npm run migrate"],
      // Traffic only moves to a new deploy once this returns 200.
      healthcheckPath: "/api/health",
      healthcheckTimeout: 120,
      // Restart the container if it crashes.
      restartPolicyType: "ON_FAILURE",
      restartPolicyMaxRetries: 10,
    },

    // One instance. Raise this (or use `railway scale`) to run more.
    replicas: 1,

    // Custom domains to attach. The generated *.up.railway.app domain is not
    // managed here; `npm run railway:setup` / `railway:domain` creates it.
    domains: CUSTOM_DOMAIN ? [CUSTOM_DOMAIN] : [],

    env: {
      // Reference variable: resolves to ${{postgres.DATABASE_URL}}, the
      // private-network URL (postgres.railway.internal). Never stored in git.
      DATABASE_URL: db.env.DATABASE_URL,
      // The private network has no TLS. See lib/db.ts.
      DATABASE_SSL: "disable",
      NODE_ENV: "production",
    },
  });

  return project(PROJECT_NAME, { resources: [db, web] });
});
