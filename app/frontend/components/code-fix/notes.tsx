// Notes never reorder and two can say the same thing, so each is keyed by its place.
export function Notes({ title, notes, warn = false }: { title: string; notes: string[]; warn?: boolean }) {
  return (
    <div className="flex min-w-0 flex-col gap-0.5">
      <span className={`font-medium ${warn ? "text-warning" : "text-fg-primary"}`}>{title}</span>
      <ul className="m-0 flex list-disc flex-col gap-0.5 pl-4">
        {notes.map((note, index) => (
          <li key={index} className="text-fg-secondary [overflow-wrap:anywhere]">{note}</li>
        ))}
      </ul>
    </div>
  )
}
