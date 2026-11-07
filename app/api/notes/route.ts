import { NextResponse } from "next/server";
import { query } from "@/lib/db";

export const dynamic = "force-dynamic";
export const runtime = "nodejs";

type NoteRow = {
  id: string; // pg returns BIGINT as string
  content: string;
  created_at: string;
};

export async function GET() {
  const rows = await query<NoteRow>(`
    SELECT id, content, created_at
    FROM notes
    ORDER BY id DESC
    LIMIT 100
  `);
  return NextResponse.json({ notes: rows });
}

export async function POST(request: Request) {
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "Invalid JSON body" }, { status: 400 });
  }

  const { content } = (body ?? {}) as { content?: string };
  const text = (content ?? "").toString().trim();
  if (!text) {
    return NextResponse.json(
      { error: "content must be a non-empty string" },
      { status: 400 }
    );
  }

  const rows = await query<{ id: string }>(
    `INSERT INTO notes (content)
     VALUES ($1)
     RETURNING id`,
    [text.slice(0, 500)]
  );

  return NextResponse.json({ id: rows[0]?.id }, { status: 201 });
}
