import { IconExternalLink } from "@tabler/icons-react"

// Pages a plan or its step points to, such as the run or the deploy, each opening in a new tab.
export function PlanLinks({ links }: { links: string[] }) {
  if (links.length === 0) {
    return null
  }

  return (
    <ul className="flex flex-wrap gap-x-3 gap-y-1">
      {links.map((link) => (
        <li key={link} className="min-w-0">
          <a
            href={link}
            target="_blank"
            rel="noreferrer"
            className="flex items-center gap-1 text-[12.5px] font-medium text-ink-2 [overflow-wrap:anywhere] hover:text-ink"
          >
            <IconExternalLink className="size-3.5 shrink-0" />
            {shownAs(link)}
          </a>
        </li>
      ))}
    </ul>
  )
}

// The address without its scheme, so a long one reads as where it goes.
function shownAs(link: string): string {
  return link.replace(/^https?:\/\//, "")
}
