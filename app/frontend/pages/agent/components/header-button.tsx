import type { ReactNode } from "react"

interface HeaderButtonProps {
  label: string
  onClick: () => void
  children: ReactNode
}

export function HeaderButton({ label, onClick, children }: HeaderButtonProps) {
  return (
    <button
      type="button"
      aria-label={label}
      title={label}
      onClick={onClick}
      className="flex size-7 items-center justify-center rounded-control text-ink-3 transition-colors duration-100 hover:bg-hover hover:text-ink"
    >
      {children}
    </button>
  )
}
