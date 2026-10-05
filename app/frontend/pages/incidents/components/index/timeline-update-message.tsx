import type { ComponentProps } from "react"
import Markdown, { type Components } from "react-markdown"
import remarkGfm from "remark-gfm"

interface TimelineUpdateMessageProps {
  text: string
  withDivider: boolean
}

const REMARK_PLUGINS = [ remarkGfm ]
// An image would load from wherever the text points, so only its alt text is kept.
const DISALLOWED_ELEMENTS = [ "img" ]

// A single line break in an update is meant, so paragraphs keep theirs rather than folding into one line.
const MARKDOWN = [
  "text-sm leading-relaxed text-muted-foreground break-words",
  "[&>:first-child]:mt-0 [&>:last-child]:mb-0",
  "[&_p]:my-2 [&_p]:whitespace-pre-line",
  "[&_ul]:my-2 [&_ul]:list-disc [&_ul]:pl-5 [&_ol]:my-2 [&_ol]:list-decimal [&_ol]:pl-5",
  "[&_li]:my-1 [&_li]:pl-0.5 [&_li]:marker:text-fg-muted [&_li>ul]:my-1 [&_li>ol]:my-1",
  "[&_a]:text-brand [&_a]:underline [&_a]:underline-offset-2 [&_a]:[overflow-wrap:anywhere]",
  "[&_strong]:font-semibold [&_strong]:text-fg-primary",
  "[&_:is(h1,h2,h3,h4,h5,h6)]:mt-3 [&_:is(h1,h2,h3,h4,h5,h6)]:mb-1 [&_:is(h1,h2,h3,h4,h5,h6)]:font-semibold [&_:is(h1,h2,h3,h4,h5,h6)]:text-fg-primary",
  "[&_code]:rounded-sm [&_code]:bg-muted [&_code]:px-1 [&_code]:font-mono [&_code]:text-[0.9em]",
  "[&_pre]:my-2 [&_pre]:overflow-x-auto [&_pre]:rounded-md [&_pre]:bg-surface-code [&_pre]:p-2.5 [&_pre_code]:bg-transparent [&_pre_code]:p-0",
  "[&_blockquote]:my-2 [&_blockquote]:border-l-2 [&_blockquote]:border-border [&_blockquote]:pl-3",
  "[&_hr]:my-3 [&_hr]:border-border",
  "[&_table]:my-2 [&_table]:block [&_table]:overflow-x-auto [&_th]:border-b [&_th]:border-border [&_th]:px-2 [&_th]:py-1 [&_th]:text-left [&_th]:font-medium",
  "[&_td]:border-b [&_td]:border-border [&_td]:px-2 [&_td]:py-1",
].join(" ")

const COMPONENTS: Components = { a: ExternalLink }

// react-markdown never renders raw HTML and drops javascript: links, so an update cannot inject markup.
export function TimelineUpdateMessage({ text, withDivider }: TimelineUpdateMessageProps) {
  return (
    <div className={withDivider ? `${MARKDOWN} mt-2 border-t border-border pt-2` : MARKDOWN}>
      <Markdown
        remarkPlugins={REMARK_PLUGINS}
        components={COMPONENTS}
        disallowedElements={DISALLOWED_ELEMENTS}
        unwrapDisallowed
      >
        {text}
      </Markdown>
    </div>
  )
}

function ExternalLink({ node: _node, ...props }: ComponentProps<"a"> & { node?: unknown }) {
  return <a {...props} target="_blank" rel="noopener noreferrer" />
}
