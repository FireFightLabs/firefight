import { IconExternalLink } from "@tabler/icons-react"

import type { Incident } from "@/pages/incidents/types"

type Page = Incident["pages"][number]

const TONE_DOT: Record<Page["tone"], string> = {
  paging: "bg-error",
  handled: "bg-success",
  problem: "bg-warning",
}

// Pages in on-call tools tied to the incident, kept in step with it both ways.
export function PagesPanel({ pages }: { pages: Incident["pages"] }) {
  if (pages.length === 0) {
    return null
  }

  return (
    <div className="rounded-xl border border-border bg-card px-5 py-4">
      <h3 className="mb-3 text-[12px] font-semibold uppercase tracking-[0.10em] text-fg-primary">Pages</h3>
      <ul className="flex flex-col gap-2.5">
        {pages.map((page) => (
          <li key={page.id} className="flex items-start gap-2.5">
            <span className={`mt-1 size-2 shrink-0 rounded-full ${TONE_DOT[page.tone]}`} aria-hidden />
            <div className="min-w-0 flex-1">
              {page.url ? (
                <a
                  href={page.url}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="inline-flex max-w-full items-center gap-1 text-[13px] leading-snug text-fg-primary hover:underline"
                >
                  <span className="truncate">{page.label}</span>
                  <IconExternalLink className="size-3 shrink-0 text-fg-muted" />
                </a>
              ) : (
                <p className="truncate text-[13px] leading-snug text-fg-primary">{page.label}</p>
              )}
              <p className="text-xs text-fg-muted">{page.stateWords}</p>
              {page.note && <p className="mt-1 text-xs text-warning">{page.note}</p>}
            </div>
          </li>
        ))}
      </ul>
    </div>
  )
}
