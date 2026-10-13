import { WordingDiff } from "@/components/handbook/wording-diff"
import { MarkdownText } from "@/components/markdown-text"
import { cn } from "@/lib/utils"

export interface SkillContent {
  usedWhen: string
  tools: string[]
  steps: string
}

interface SkillContentDiffProps {
  before: SkillContent | null
  after: SkillContent
  beforeLabel: string
  afterLabel: string
  // The text size and colour of the surface it sits on, a page or a card in the chat.
  textClassName?: string
  labelClassName?: string
}

type ToolChange = "added" | "removed" | "kept"

const TOOL_TONES: Record<ToolChange, string> = {
  added: "bg-success-tint text-success",
  removed: "bg-error-tint text-error line-through",
  kept: "bg-muted text-fg-secondary",
}

const TOOL_WORDS: Record<ToolChange, string> = {
  added: "added",
  removed: "removed",
  kept: "kept",
}

function toolChanges(before: SkillContent | null, after: SkillContent): [string, ToolChange][] {
  if (!before) {
    return after.tools.map((tool) => [ tool, "kept" ])
  }
  const kept: [string, ToolChange][] = after.tools.map((tool) => [ tool, before.tools.includes(tool) ? "kept" : "added" ])
  const removed: [string, ToolChange][] = before.tools.filter((tool) => !after.tools.includes(tool)).map((tool) => [ tool, "removed" ])
  return [ ...kept, ...removed ]
}

// What a skill would say beside what it says now: when it is used and its steps with the words that change marked, and
// its tools with the ones added and removed. With nothing before, it is the skill as it would be.
export function SkillContentDiff({ before, after, beforeLabel, afterLabel, textClassName, labelClassName }: SkillContentDiffProps) {
  const label = cn("text-xs font-medium text-muted-foreground", labelClassName)
  const stepsChanged = before !== null && before.steps !== after.steps

  return (
    <div className="flex min-w-0 flex-col gap-4">
      <section className="flex flex-col gap-1">
        <h4 className={label}>When Halon uses it</h4>
        {before && before.usedWhen !== after.usedWhen
          ? <WordingDiff before={before.usedWhen} after={after.usedWhen} side="after" className={textClassName} />
          : <MarkdownText text={after.usedWhen} className={textClassName} />}
      </section>
      <section className="flex flex-col gap-1.5">
        <h4 className={label}>Tools</h4>
        {after.tools.length === 0 && !before?.tools.length
          ? <p className={cn("text-sm text-muted-foreground", textClassName)}>None</p>
          : (
            <ul className="flex flex-wrap gap-1.5">
              {toolChanges(before, after).map(([ tool, change ]) => (
                <li key={tool} className={cn("rounded px-1.5 py-0.5 font-mono text-xs", TOOL_TONES[change])}>
                  {tool}
                  {change !== "kept" && <span className="sr-only"> ({TOOL_WORDS[change]})</span>}
                </li>
              ))}
            </ul>
          )}
      </section>
      {stepsChanged && before ? (
        <div className="grid gap-4 lg:grid-cols-2">
          <section className="flex min-w-0 flex-col gap-1">
            <h4 className={label}>{beforeLabel}</h4>
            <div className="[overflow-wrap:anywhere]">
              <WordingDiff before={before.steps} after={after.steps} side="before" className={cn("text-fg-muted", textClassName)} />
            </div>
          </section>
          <section className="flex min-w-0 flex-col gap-1">
            <h4 className={label}>{afterLabel}</h4>
            <div className="[overflow-wrap:anywhere]">
              <WordingDiff before={before.steps} after={after.steps} side="after" className={textClassName} />
            </div>
          </section>
        </div>
      ) : (
        <section className="flex min-w-0 flex-col gap-1">
          <h4 className={label}>Steps</h4>
          <div className="[overflow-wrap:anywhere]">
            <MarkdownText text={after.steps} className={textClassName} />
          </div>
        </section>
      )}
    </div>
  )
}
