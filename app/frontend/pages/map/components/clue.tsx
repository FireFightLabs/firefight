// A clue that ends in an address links to where it was seen.
const TRAILING_LINK = /^(.*\S)\s+(https:\/\/\S+)$/

export function Clue({ clue }: { clue: string }) {
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
