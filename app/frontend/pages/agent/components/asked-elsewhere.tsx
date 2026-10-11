import { IconArrowUpRight, IconMessageCircle } from "@tabler/icons-react"

interface AskedElsewhereProps {
  // Where the chat lives, as people know it, such as Slack.
  place: string
  url: string | null
}

// Stands where the composer would. A chat asked elsewhere is answered there, so it is read here and carried on there.
export function AskedElsewhere({ place, url }: AskedElsewhereProps) {
  return (
    <div className="mx-auto flex w-full max-w-3xl flex-col gap-2 rounded-card bg-surface px-3.5 py-3 shadow-card sm:flex-row sm:items-center sm:justify-between">
      <div className="flex items-start gap-2.5">
        <IconMessageCircle className="mt-px size-4 shrink-0 text-ink-3" />
        <p className="text-[13px] leading-snug text-ink-2">
          <span className="font-medium text-ink">This chat is in {place}. </span>
          Halon answers it there, so carry on in {place} to ask more.
        </p>
      </div>
      {url && (
        <a
          href={url}
          className="inline-flex shrink-0 items-center gap-1.5 self-end rounded-full bg-primary px-3 py-1.5 text-[13px] font-medium text-primary-foreground transition-colors duration-150 hover:bg-[var(--btn-primary-hover)] sm:self-auto"
        >
          Open in {place}
          <IconArrowUpRight className="size-3.5" />
        </a>
      )}
    </div>
  )
}
