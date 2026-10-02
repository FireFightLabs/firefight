import type { Icon } from "@tabler/icons-react"

interface ListButtonProps {
  icon: Icon
  label: string
  onClick: () => void
  className?: string
}

export function ListButton({ icon: ButtonIcon, label, onClick, className = "flex" }: ListButtonProps) {
  return (
    <button
      type="button"
      onClick={onClick}
      aria-label={label}
      title={label}
      className={`${className} size-7 items-center justify-center rounded-control text-ink-2 transition-colors duration-150 hover:bg-hover hover:text-ink active:bg-hover-2`}
    >
      <ButtonIcon className="size-4" />
    </button>
  )
}
