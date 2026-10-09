import { IconCheck, IconCopy } from "@tabler/icons-react"
import { type ComponentProps, isValidElement, type ReactNode, useEffect, useRef, useState } from "react"
import Markdown, { type Components } from "react-markdown"
import remarkGfm from "remark-gfm"

import { fenceLanguage, highlight } from "@/lib/code-highlight"
import { newTabAttributes } from "@/lib/links"

interface AnswerTextProps {
  text: string
}

const REMARK_PLUGINS = [ remarkGfm ]
const COPIED_MS = 1600

// The plugin wraps inline code in backticks and quotes in quote marks, which read as typos in an answer.
const PROSE = [
  "agent-answer prose prose-sm max-w-none min-w-0 text-[14px] leading-[1.7]",
  "[&>:first-child]:mt-0 [&>:last-child]:mb-0",
  "prose-p:my-2.5 prose-ul:my-2.5 prose-ol:my-2.5 prose-ul:pl-5 prose-ol:pl-5 prose-li:my-1 prose-li:pl-0.5",
  "prose-headings:mt-6 prose-headings:mb-2 prose-headings:font-semibold prose-headings:tracking-[-0.01em] prose-headings:text-balance",
  "prose-h1:text-[17px] prose-h2:text-[15.5px] prose-h3:text-[14px] prose-h4:text-[14px]",
  "prose-a:underline-offset-3 prose-a:decoration-accent/45 hover:prose-a:decoration-accent",
  "prose-code:rounded-[5px] prose-code:bg-inset prose-code:px-[0.4em] prose-code:py-[0.12em] prose-code:text-[0.86em] prose-code:font-medium",
  "prose-code:shadow-hairline prose-code:before:content-none prose-code:after:content-none",
  "prose-blockquote:my-3 prose-blockquote:border-l-2 prose-blockquote:border-line-strong prose-blockquote:pl-3.5",
  "prose-blockquote:font-normal prose-blockquote:not-italic prose-blockquote:text-ink-2",
  "[&_blockquote_p]:before:content-none [&_blockquote_p]:after:content-none",
].join(" ")

// Outside the plugin, so its margins and padding stay out of the frame. Inline code keeps the chip it has in prose.
const TABLE = [
  "w-full border-collapse text-left text-[13px] leading-normal text-ink tabular-nums",
  "[&_thead]:bg-inset [&_th]:border-b [&_th]:border-line [&_th]:px-3 [&_th]:py-2 [&_th]:text-[12px] [&_th]:font-medium [&_th]:text-ink-2",
  "[&_td]:border-b [&_td]:border-line [&_td]:px-3 [&_td]:py-2 [&_tbody_tr:last-child_td]:border-0",
  "[&_code]:rounded-[5px] [&_code]:bg-inset [&_code]:px-1 [&_code]:font-mono [&_code]:text-[0.9em] [&_strong]:font-semibold",
].join(" ")

// A wide table or a long line of code scrolls in its own frame, so the thread never grows sideways on a phone.
const COMPONENTS: Components = {
  a: AnswerLink,
  pre: CodeBlock,
  table: Table,
}

// react-markdown never renders raw HTML, so a reply cannot inject markup.
export function AnswerText({ text }: AnswerTextProps) {
  return (
    <div className={PROSE}>
      <Markdown remarkPlugins={REMARK_PLUGINS} components={COMPONENTS}>{text}</Markdown>
    </div>
  )
}

type Rendered<Tag extends "a" | "pre" | "table"> = ComponentProps<Tag> & { node?: unknown }

function AnswerLink({ node: _node, ...props }: Rendered<"a">) {
  return <a {...props} {...newTabAttributes(props.href)} />
}

function Table({ node: _node, ...props }: Rendered<"table">) {
  return (
    <div className="not-prose my-3 overflow-x-auto rounded-card shadow-hairline">
      <table {...props} className={TABLE} />
    </div>
  )
}

interface Fenced {
  code: string
  language: string | undefined
}

// The text and the language of the code react-markdown put inside a fenced block's pre.
function fenced(children: ReactNode): Fenced | null {
  if (!isValidElement<{ className?: string; children?: ReactNode }>(children)) {
    return null
  }
  const text = children.props.children
  return typeof text === "string" ? { code: text.replace(/\n$/, ""), language: fenceLanguage(children.props.className) } : null
}

// The block highlighted once its language has loaded, plain until then and whenever it cannot be.
function useHighlighted(block: Fenced | null): string | null {
  const [ shown, setShown ] = useState<{ code: string; html: string | null } | null>(null)
  const code = block?.code
  const language = block?.language

  useEffect(() => {
    if (code === undefined) {
      return
    }
    let current = true
    highlight(code, language).then((html) => {
      if (current) {
        setShown({ code, html })
      }
    }).catch(() => undefined)
    return () => {
      current = false
    }
  }, [ code, language ])

  return shown && shown.code === code ? shown.html : null
}

// What the agent hands over as code is usually meant to be pasted somewhere, a WAF rule or a query, so it copies in one
// click. A fenced block is highlighted in its language, or in the one it most likely is when the fence names none.
function CodeBlock({ node: _node, children, ...props }: Rendered<"pre">) {
  const block = useRef<HTMLPreElement>(null)
  const [ copied, setCopied ] = useState(false)
  const source = fenced(children)
  const html = useHighlighted(source)

  useEffect(() => {
    if (!copied) {
      return
    }
    const timer = setTimeout(() => setCopied(false), COPIED_MS)
    return () => clearTimeout(timer)
  }, [ copied ])

  function copy() {
    navigator.clipboard.writeText(block.current?.innerText ?? "")
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
