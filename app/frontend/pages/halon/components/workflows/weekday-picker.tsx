import { ToggleGroup, ToggleGroupItem } from "@/components/ui/toggle-group"

const DAY_NAMES = [ "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" ]

// Days of the week, Sunday as 0, as a schedule keeps them.
export function WeekdayPicker({ days, onChange }: { days: number[]; onChange: (days: number[]) => void }) {
  function choose(values: string[]) {
    onChange(values.map(Number).sort((first, second) => first - second))
  }

  return (
    <ToggleGroup type="multiple" variant="outline" value={days.map(String)} onValueChange={choose} className="flex-wrap">
      {DAY_NAMES.map((day, index) => (
        <ToggleGroupItem key={day} value={String(index)} aria-label={day} className="px-2.5">{day}</ToggleGroupItem>
      ))}
    </ToggleGroup>
  )
}
