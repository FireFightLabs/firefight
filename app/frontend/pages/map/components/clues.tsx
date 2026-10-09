import { Clue } from "@/pages/map/components/clue"

// What Firefight saw that suggests a link, one line each, so a person can judge it before confirming.
export function Clues({ clues }: { clues: string[] }) {
  return (
    <ul className="flex list-disc flex-col gap-0.5 pl-4 text-xs text-muted-foreground">
      {clues.map((clue, index) => (
        <Clue key={`${index}:${clue}`} clue={clue} />
      ))}
    </ul>
  )
}
