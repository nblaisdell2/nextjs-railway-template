import Link from "next/link";
import { query } from "@/lib/db";
import AddNoteForm from "./AddNoteForm";

// This page reads live data from Postgres on every request.
export const dynamic = "force-dynamic";

type NoteRow = {
  id: string;
  content: string;
  created_at: string;
};

export default async function DemoPage() {
  const notes = await query<NoteRow>(`
    SELECT id, content, created_at::date::text AS created_at
    FROM notes
    ORDER BY id DESC
    LIMIT 25
  `);

  return (
    <main className="container">
      <div className="brand">
        <span className="dot" />
        <Link href="/" style={{ color: "inherit", textDecoration: "none" }}>
          Site Template
        </Link>
      </div>

      <h1 style={{ fontSize: "1.8rem" }}>Database demo</h1>
      <p className="muted">
        Every note below is a row in Postgres, read server-side on each request
        and written through a route handler. Replace this page with your own
        app.
      </p>

      <h2 style={{ fontSize: "1.2rem", marginTop: "2rem" }}>Add a note</h2>
      <AddNoteForm />

      <h2 style={{ fontSize: "1.2rem", marginTop: "2rem" }}>Latest notes</h2>
      <div className="card">
        {notes.length === 0 ? (
          <p className="muted" style={{ margin: 0 }}>
            No notes yet — add one above.
          </p>
        ) : (
          <table>
            <thead>
              <tr>
                <th>Date</th>
                <th>Note</th>
              </tr>
            </thead>
            <tbody>
              {notes.map((n) => (
                <tr key={n.id}>
                  <td style={{ whiteSpace: "nowrap" }}>{n.created_at}</td>
                  <td>{n.content}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    </main>
  );
}
