import { NextResponse } from "next/server";
import { query } from "@/lib/db";

// Never cache: Railway calls this during every deploy (healthcheck in
// .railway/railway.ts) and only switches traffic over once it returns 200.
export const dynamic = "force-dynamic";
export const runtime = "nodejs";

export async function GET() {
  const started = Date.now();
  try {
    const rows = await query<{ now: string }>("SELECT now() AS now");
    return NextResponse.json({
      status: "ok",
      db: "up",
      dbTime: rows[0]?.now ?? null,
      latencyMs: Date.now() - started,
    });
  } catch (err) {
    // Log so the failure shows up in `railway logs`, not just the HTTP response.
    console.error("[health] DB check failed:", err);
    return NextResponse.json(
      {
        status: "degraded",
        db: "down",
        error: err instanceof Error ? err.message : String(err),
      },
      { status: 503 }
    );
  }
}
