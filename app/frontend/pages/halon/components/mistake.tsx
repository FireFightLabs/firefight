import { Link } from "@inertiajs/react"
import { IconBrain } from "@tabler/icons-react"

import { formatDate } from "@/lib/formatters"
import { incidentPath, investigationPath } from "@/lib/routes"
import type { HalonMistake } from "@/types/serializers"

export function Mistake({ mistake }: { mistake: HalonMistake }) {
  return (
    <li className="flex flex-col gap-2 border-b border-border px-5 py-4 last:border-b-0">
      <div className="flex flex-wrap items-baseline justify-between gap-x-4 gap-y-1">
        {mistake.incidentId ? (
          <Link href={incidentPath(mistake.incidentId)} className="font-medium text-fg-primary hover:underline">
            {mistake.label}
          </Link>
        ) : (
          <span className="font-medium text-fg-primary">{mistake.label}</span>
        )}
        {mistake.markedAt && <span className="text-xs text-fg-secondary">Marked wrong {formatDate(mistake.markedAt)}</span>}
      </div>
      <p className="text-sm text-fg-body">
        <span className="text-fg-secondary">Halon said: </span>
        {mistake.summary}
      </p>
      {mistake.cause && <p className="text-xs text-fg-secondary">The cause it gave: {mistake.cause}</p>}
      {mistake.lessons.length > 0 ? (
        <ul className="flex flex-col gap-1">
          {mistake.lessons.map((lesson) => (
            <li key={lesson.id} className="flex items-start gap-1.5 text-sm text-fg-body">
              <IconBrain className="mt-0.5 size-3.5 shrink-0 text-brand" />
              <span>
                {lesson.text}
                <span className="ml-1.5 text-xs text-fg-secondary">{lesson.confirmed ? "confirmed" : "unconfirmed"}</span>
              </span>
            </li>
          ))}
        </ul>
      ) : (
        <p className="text-xs text-fg-secondary">Nothing learned from this incident yet.</p>
      )}
      <Link href={investigationPath(mistake.investigationId)} className="w-fit text-xs text-fg-secondary hover:text-fg-primary hover:underline">
        Open the investigation
      </Link>
    </li>
  )
}
