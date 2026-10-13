interface StarterButtonProps {
  starter: string
  onPick: (starter: string) => void
}

// An example question for Halon, handed to the composer to finish rather than sent.
export function StarterButton({ starter, onPick }: StarterButtonProps) {
  return (
    <button
      type="button"
      onClick={() => onPick(starter)}
      className="rounded-lg border border-border px-3 py-2 text-left text-[13px] text-fg-secondary hover:bg-surface-hover hover:text-fg-primary"
    >
      {starter}
    </button>
  )
}
