import { useMemo } from "react"

import { SearchableSelect } from "@/components/searchable-select"

export function browserTimeZone(): string {
  return Intl.DateTimeFormat().resolvedOptions().timeZone
}

export function TimeZoneSelect({
  id,
  value,
  onChange,
  timeZones,
}: {
  id: string
  value: string
  onChange: (zone: string) => void
  timeZones: string[]
}) {
  const options = useMemo(() => timeZones.map((zone) => ({ value: zone, label: zone.split("_").join(" ") })), [ timeZones ])

  function choose(zone: string | null) {
    if (zone) {
      onChange(zone)
    }
  }

  return (
    <SearchableSelect
      id={id}
      value={value}
      onValueChange={choose}
      options={options}
      placeholder="Pick a time zone"
      searchPlaceholder="Search time zones"
      emptyText="No time zones match"
    />
  )
}
