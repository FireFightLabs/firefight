import { PulseMark } from "@/components/code-fix/pulse-mark"

export function WaitingLine({ words }: { words: string }) {
  return (
    <span className="flex items-start gap-2 text-fg-primary">
      <PulseMark />
      {words}
    </span>
  )
}
