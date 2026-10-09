import type { PointingSetting } from "@/pages/map/lib/pointing"

export function PointingSettingRow({ setting, onPick }: { setting: PointingSetting; onPick: (resourceId: string) => void }) {
  function pickService() {
    onPick(setting.from.id)
  }

  return (
    <li>
      <code className="font-mono text-xs">{setting.variable}</code> from{" "}
      <button type="button" onClick={pickService} className="font-semibold hover:underline">
        {setting.from.name}
      </button>
    </li>
  )
}
