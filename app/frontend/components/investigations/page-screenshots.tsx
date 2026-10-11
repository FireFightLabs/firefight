import type { ChatScreenshot } from "@/types/serializers"

// The pages the run's browser saw under one step, one per screen size, each opening whole in a new tab.
export function PageScreenshots({ screenshots }: { screenshots: ChatScreenshot[] }) {
  if (screenshots.length === 0) {
    return null
  }

  return (
    <div className={`mt-3 grid gap-2 ${screenshots.length > 1 ? "sm:grid-cols-2" : ""}`}>
      {screenshots.map((screenshot) => (
        <figure key={screenshot.id} className="overflow-hidden rounded-lg border border-border bg-surface-card">
          <a href={screenshot.path} target="_blank" rel="noreferrer" className="block border-b border-border">
            <img src={screenshot.path} alt={screenshot.caption} loading="lazy" className="block h-52 w-full object-cover object-top" />
          </a>
          <figcaption className="px-3 py-2 text-xs leading-5 break-words text-fg-secondary">{screenshot.caption}</figcaption>
        </figure>
      ))}
    </div>
  )
}
