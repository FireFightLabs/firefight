import Markdown, { type Components } from "react-markdown"
import remarkGfm from "remark-gfm"

import { AnswerLink } from "@/pages/agent/components/answer-link"
import { AnswerTable } from "@/pages/agent/components/answer-table"
import { CodeBlock } from "@/pages/agent/components/code-block"

interface AnswerTextProps {
  text: string
}

const REMARK_PLUGINS = [ remarkGfm ]

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

// A wide table or a long line of code scrolls in its own frame, so the thread never grows sideways on a phone.
const COMPONENTS: Components = {
  a: AnswerLink,
  pre: CodeBlock,
  table: AnswerTable,
}

// react-markdown never renders raw HTML, so a reply cannot inject markup.
export function AnswerText({ text }: AnswerTextProps) {
  return (
    <div className={PROSE}>
      <Markdown remarkPlugins={REMARK_PLUGINS} components={COMPONENTS}>{text}</Markdown>
    </div>
  )
}
