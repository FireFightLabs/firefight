import { Input } from "@/components/ui/input"

// One picker for every colour field: a swatch that opens the OS picker, plus a
// hex field for pasting a brand colour. Types and catalogue types used to offer
// a fixed palette instead, which quietly made some colours unreachable.
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
        onChange={(e) => onChange(e.target.value)}
        className="h-9 w-12 cursor-pointer p-1"
      />
      <Input
        value={value}
        onChange={(e) => onChange(e.target.value)}
        className="flex-1 font-mono text-sm"
        placeholder="#3B82F6"
        aria-label="Colour hex value"
      />
    </div>
  )
}
