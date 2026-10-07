import { MarkdownText } from "@/components/markdown-text"

interface TimelineUpdateMessageProps {
  text: string
  withDivider: boolean
}

export function TimelineUpdateMessage({ text, withDivider }: TimelineUpdateMessageProps) {
  return <MarkdownText text={text} className={withDivider ? "mt-2 border-t border-border pt-2" : undefined} />
}
