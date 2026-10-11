import type { ChatScreenshot } from "@/types/serializers"

// The pages Halon's browser saw, one per screen size, two across when there is more than one. Each opens whole in a new
// tab, and its caption names the screen size, the page and whether the check stopped before something it would send.
export function ScreenshotGrid({ screenshots }: { screenshots: ChatScreenshot[] }) {
  return (
    <div className={`grid w-full gap-2 ${screenshots.length > 1 ? "max-w-160 sm:grid-cols-2" : "max-w-110"}`}>
      {screenshots.map((screenshot) => (
        <figure key={screenshot.id} className="overflow-hidden rounded-card bg-surface shadow-card">
          <a href={screenshot.path} target="_blank" rel="noreferrer" className="block border-b border-line">
            <img src={screenshot.path} alt={screenshot.caption} loading="lazy" className="block h-52 w-full object-cover object-top" />
          </a>
          <figcaption className="px-3 py-2 text-[12.5px] leading-5 break-words text-ink-2">{screenshot.caption}</figcaption>
        </figure>
      ))}
    </div>
  )
}
