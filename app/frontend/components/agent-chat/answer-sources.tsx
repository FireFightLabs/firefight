import { useState } from "react"

import { newTabAttributes } from "@/lib/links"
import type { AnswerSource } from "@/lib/agent-chat/types"

// Past this many the list is folded behind a count, so a long investigation's answer stays readable.
const SHOWN = 12

// What Halon read to give this answer, from the turn's own calls, folded under it so it is there when someone checks.
export function AnswerSources({ sources }: { sources: AnswerSource[] }) {
  const [ open, setOpen ] = useState(false)
  const toggle = () => setOpen((shown) => !shown)
  const listed = sources.slice(0, SHOWN)
  const more = sources.length - listed.length

  return (
    <div className="flex min-w-0 flex-col gap-1 text-[11.5px] leading-4 text-ink-3">
      <button type="button" onClick={toggle} aria-expanded={open} className="flex w-fit items-center gap-1 hover:text-ink-2">
        <svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round"
          strokeLinejoin="round" className={open ? "rotate-90 transition-transform" : "transition-transform"} aria-hidden>
          <path d="M9 6l6 6-6 6" />
        </svg>
        {sources.length === 1 ? "Read 1 source" : `Read ${sources.length} sources`}
      </button>
      {open && (
        <ul className="flex min-w-0 flex-col gap-0.5 pl-3.5">
          {listed.map((source) => (
            <li key={`${source.title}-${source.url ?? ""}`} className="truncate">
              {source.url ? (
                <a href={source.url} {...newTabAttributes(source.url)} className="underline decoration-line-strong underline-offset-2 hover:text-ink-2">
                  {source.title}
                </a>
              ) : (
                source.title
              )}
            </li>
          ))}
          {more > 0 && <li>{`and ${more} more`}</li>}
        </ul>
      )}
    </div>
  )
}
