// The steps a claim or a theory rests on, each a link down to that step.
export function StepLinks({ steps }: { steps: number[] }) {
  if (steps.length === 0) {
    return null
  }

  return (
    <span className="text-muted-foreground inline-flex flex-wrap gap-1 text-xs">
      {steps.length === 1 ? "step" : "steps"}
      {steps.map((position) => (
        <a key={position} href={`#step-${position}`} className="text-foreground rounded border px-1.5 hover:bg-muted">
          {position}
        </a>
      ))}
    </span>
  )
}
