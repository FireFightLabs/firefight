// What a new chat shows around the composer before the first question: a heading above it and example questions below it.

interface Example {
  label: string
  draft: string
}

// A draft ending in @ opens the incident menu as soon as it lands in the composer.
const EXAMPLES: Example[] = [
  { label: "Which incidents are open?", draft: "Which incidents are open?" },
  { label: "What changed before an incident?", draft: "What changed before @" },
  { label: "Has this happened before?", draft: "Has this happened before with @" },
]

const RISE = "fade-up 450ms var(--ease-out-strong)"

export function StartHeading() {
  return (
    <div className="flex flex-1 flex-col items-center justify-end px-4 pb-5">
      <h2 className="text-center text-[22px] font-semibold text-ink" style={{ animation: `${RISE} both` }}>
        What do you want to know?
      </h2>
    </div>
  )
}

interface StartExamplesProps {
  onPick: (draft: string) => void
}

export function StartExamples({ onPick }: StartExamplesProps) {
  return (
    <div className="flex flex-wrap justify-center gap-2 px-4 pt-1">
      {EXAMPLES.map((example, index) => (
        <ExampleButton key={example.label} example={example} index={index} onPick={onPick} />
      ))}
    </div>
  )
}

interface ExampleButtonProps {
  example: Example
  index: number
  onPick: (draft: string) => void
}

function ExampleButton({ example, index, onPick }: ExampleButtonProps) {
  function pick() {
    onPick(example.draft)
  }

  return (
    <button
      type="button"
      onClick={pick}
      className="rounded-full border border-line bg-surface px-3.5 py-1.5 text-[13px] text-ink-2 shadow-hairline transition-colors duration-150 hover:bg-hover hover:text-ink"
      style={{ animation: `${RISE} ${120 + index * 60}ms both` }}
    >
      {example.label}
    </button>
  )
}
