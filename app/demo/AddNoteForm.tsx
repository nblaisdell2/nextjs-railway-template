"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";

export default function AddNoteForm() {
  const router = useRouter();
  const [content, setContent] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      const res = await fetch("/api/notes", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ content }),
      });
      if (!res.ok) {
        const data = await res.json().catch(() => ({}));
        throw new Error(data.error ?? `Request failed (${res.status})`);
      }
      setContent("");
      router.refresh(); // re-runs the server component to show the new row
    } catch (err) {
      setError(err instanceof Error ? err.message : "Something went wrong");
    } finally {
      setBusy(false);
    }
  }

  return (
    <form className="row" onSubmit={submit}>
      <input
        aria-label="Note"
        placeholder="Write something…"
        value={content}
        onChange={(e) => setContent(e.target.value)}
        style={{ flex: "2 1 240px" }}
      />
      <button className="btn" type="submit" disabled={busy}>
        {busy ? "Adding…" : "Add"}
      </button>
      {error && (
        <span className="amount-neg" style={{ flexBasis: "100%" }}>
          {error}
        </span>
      )}
    </form>
  );
}
