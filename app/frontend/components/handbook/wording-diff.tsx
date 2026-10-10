import HtmlDiff from "htmldiff-js"
import { useMemo } from "react"
import { renderToStaticMarkup } from "react-dom/server"

import { MarkdownText } from "@/components/markdown-text"

// What the page says now shows the words a proposal removes struck through, and what Halon would write shows the words
// it adds marked. Both come from one diff of the rendered pages, each side without the other side's words. The diff marks
// each word on its own, so neighbouring marks are joined and a changed phrase reads as one.
const SIDES = {
  before: {
    className: "[&_del]:rounded-sm [&_del]:bg-error-tint [&_del]:px-0.5 [&_del]:text-error [&_del]:line-through",
    others: /<ins\b[^>]*>[\s\S]*?<\/ins>/g,
    split: /<\/del>(\s+)<del\b[^>]*>/g,
  },
  after: {
    className: "[&_ins]:rounded-sm [&_ins]:bg-success-tint [&_ins]:px-0.5 [&_ins]:text-success [&_ins]:no-underline",
    others: /<del\b[^>]*>[\s\S]*?<\/del>/g,
    split: /<\/ins>(\s+)<ins\b[^>]*>/g,
  },
}

interface WordingDiffProps {
  before: string
  after: string
  side: keyof typeof SIDES
  className?: string
}

// One side of a proposed edit with its changes marked. The markup comes from MarkdownText, which never renders raw HTML,
// and the diff only wraps its words, so nothing in either wording becomes markup. A diff that cannot be made shows the
// side's own wording plainly.
export function WordingDiff({ before, after, side, className }: WordingDiffProps) {
  const diff = useMemo(() => {
    try {
      const marked = HtmlDiff.execute(
        renderToStaticMarkup(<MarkdownText text={before} className={className} />),
        renderToStaticMarkup(<MarkdownText text={after} className={className} />),
      )
      return marked.replace(SIDES[side].others, "").replace(SIDES[side].split, "$1")
    } catch {
      return null
    }
  }, [ before, after, side, className ])

  if (!diff) {
    return <MarkdownText text={side === "before" ? before : after} className={className} />
  }

  return <div className={SIDES[side].className} dangerouslySetInnerHTML={{ __html: diff }} />
}
