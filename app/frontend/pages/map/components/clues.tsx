// What Firefight saw that suggests a link, one line each, so a person can judge it before confirming. A clue that ends
// in an address links to where it was seen.
const TRAILING_LINK = /^(.*\S)\s+(https:\/\/\S+)$/

function Clue({ clue }: { clue: string }) {
  const match = TRAILING_LINK.exec(clue)
  if (!match) {
    return <li>{clue}</li>
  }
  return (
    <li>
      <a href={match[2]} target="_blank" rel="noreferrer" className="underline decoration-dotted underline-offset-2 hover:text-foreground">
        {match[1]}
      </a>
    </li>
  )
}

export function Clues({ clues }: { clues: string[] }) {
  return (
    <ul className="flex list-disc flex-col gap-0.5 pl-4 text-xs text-muted-foreground">
      {clues.map((clue) => (
        <Clue key={clue} clue={clue} />
      ))}
    </ul>
  )
}
