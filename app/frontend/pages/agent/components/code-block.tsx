import { IconCheck, IconCopy } from "@tabler/icons-react"
import { useEffect, useRef, useState } from "react"

import { fenced, useHighlighted } from "@/pages/agent/hooks/use-highlighted"
import type { RenderedTag } from "@/pages/agent/types"

const COPIED_MS = 1600

// What the agent hands over as code is usually meant to be pasted somewhere, a WAF rule or a query, so it copies in one
// click. A fenced block is highlighted in its language, or in the one it most likely is when the fence names none.
export function CodeBlock({ node: _node, children, ...props }: RenderedTag<"pre">) {
  const block = useRef<HTMLPreElement>(null)
  const [ copied, setCopied ] = useState(false)
  const source = fenced(children)
  const html = useHighlighted(source)

  useEffect(() => {
    if (!copied) {
      return
    }
    const timer = setTimeout(clearCopied, COPIED_MS)
    return () => clearTimeout(timer)
  }, [ copied ])

  function clearCopied() {
    setCopied(false)
  }

  // A refused clipboard, in an insecure page or without permission, never shows Copied.
  function copy() {
    void navigator.clipboard.writeText(block.current?.innerText ?? "").then(markCopied)
  }

  function markCopied() {
    setCopied(true)
  }

  return (
    <div className="group/code not-prose relative my-3 overflow-hidden rounded-card bg-surface-code shadow-hairline">
      <pre
        ref={block}
        {...props}
        className="overflow-x-auto px-3.5 py-3 pr-11 font-mono text-[12.5px] leading-[1.65] text-ink"
      >
        {html === null ? children : <code className="hljs" dangerouslySetInnerHTML={{ __html: html }} />}
      </pre>
      <button
        type="button"
        onClick={copy}
        aria-label={copied ? "Copied" : "Copy code"}
        title={copied ? "Copied" : "Copy code"}
        className="absolute top-1.5 right-1.5 flex size-7 items-center justify-center rounded-control bg-inset text-ink-3 opacity-0 transition-[opacity,color,background-color] duration-150 group-hover/code:opacity-100 hover:bg-hover-2 hover:text-ink focus-visible:opacity-100 [@media(hover:none)]:opacity-100"
      >
        {copied ? <IconCheck className="size-3.5 text-green" /> : <IconCopy className="size-3.5" />}
      </button>
    </div>
  )
}
