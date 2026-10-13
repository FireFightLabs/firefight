// A value a step took in or gave back, written out as JSON in a box that scrolls rather than stretching the panel.
export function JsonBlock({ label, value }: { label: string; value: unknown }) {
  const empty = value === null || value === undefined || (typeof value === "object" && Object.keys(value).length === 0)

  return (
    <section className="space-y-1">
      <h5 className="text-[11px] font-medium text-fg-secondary">{label}</h5>
      {empty ? (
        <p className="text-xs text-fg-muted">Nothing.</p>
      ) : (
        <pre className="max-h-56 overflow-auto rounded-sm border border-border bg-surface-code px-2.5 py-2 font-mono text-[11px] leading-relaxed whitespace-pre-wrap text-fg-primary [overflow-wrap:anywhere]">
          {JSON.stringify(value, null, 2)}
        </pre>
      )}
    </section>
  )
}
