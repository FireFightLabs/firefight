import Markdown from "react-markdown"
import remarkGfm from "remark-gfm"

interface AnswerTextProps {
  text: string
}

const REMARK_PLUGINS = [ remarkGfm ]

// The agent writes markdown. Raw HTML in it is never rendered, so a reply cannot inject markup.
export function AnswerText({ text }: AnswerTextProps) {
  return (
    <div className="agent-answer prose prose-sm max-w-none text-[14px] leading-7">
      <Markdown remarkPlugins={REMARK_PLUGINS}>{text}</Markdown>
    </div>
  )
}
