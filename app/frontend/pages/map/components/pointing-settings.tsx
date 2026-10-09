import { PointingSettingRow } from "@/pages/map/components/pointing-setting-row"
import type { PointingSetting } from "@/pages/map/lib/pointing"

export function PointingSettings({ settings, onPick }: { settings: PointingSetting[]; onPick: (resourceId: string) => void }) {
  return (
    <ul className="flex flex-col gap-1 text-sm">
      {settings.map((setting) => (
        <PointingSettingRow key={setting.key} setting={setting} onPick={onPick} />
      ))}
    </ul>
  )
}
