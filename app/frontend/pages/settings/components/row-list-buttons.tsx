import { IconPlus, IconTrash } from "@tabler/icons-react"

import { Button } from "@/components/ui/button"

export function AddRowButton({ label, onClick }: { label: string; onClick: () => void }) {
  return (
    <Button type="button" variant="outline" size="sm" className="self-start" onClick={onClick}>
      <IconPlus className="size-4" />
      {label}
    </Button>
  )
}

export function RemoveRowButton({ label, onClick }: { label: string; onClick: () => void }) {
  return (
    <Button
      type="button"
      variant="ghost"
      size="icon"
      className="size-8 text-muted-foreground"
      aria-label={label}
      onClick={onClick}
    >
      <IconTrash className="size-4" />
    </Button>
  )
}
