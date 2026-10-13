import type { HalonSkillToolChoice } from "@/types/serializers"

// A tool in the skill editor's picker: its name as Halon calls it, where it comes from and what it does.
export function SkillToolOption({ choice }: { choice: HalonSkillToolChoice | undefined }) {
  if (!choice) {
    return null
  }

  return (
    <div className="flex min-w-0 flex-col">
      <span className="font-mono text-xs">{choice.name}</span>
      <span className="truncate text-xs text-muted-foreground">{choice.group}. {choice.description}</span>
    </div>
  )
}
