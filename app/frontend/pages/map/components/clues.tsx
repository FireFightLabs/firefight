// What Firefight saw that suggests a link, one line each, so a person can judge it before confirming.
export function Clues({ clues }: { clues: string[] }) {
  return (
    <ul className="flex list-disc flex-col gap-0.5 pl-4 text-xs text-muted-foreground">
      {clues.map((clue) => (
        <li key={clue}>{clue}</li>
      ))}
    </ul>
  )
}
