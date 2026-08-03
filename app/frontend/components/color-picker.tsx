import { Input } from "@/components/ui/input"

export function ColorPicker({
  id,
  value,
  onChange,
}: {
  id: string
  value: string
  onChange: (color: string) => void
}) {
  return (
    <div className="flex items-center gap-2">
      <Input
        id={id}
        type="color"
        value={value}
        onChange={(event) => onChange(event.target.value)}
        className="h-9 w-12 cursor-pointer p-1"
      />
      <Input
        value={value}
        onChange={(event) => onChange(event.target.value)}
        className="flex-1 font-mono text-sm"
        placeholder="#3B82F6"
        aria-label="Colour hex value"
      />
    </div>
  )
}
