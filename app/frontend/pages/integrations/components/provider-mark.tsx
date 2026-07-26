import { useState } from "react"

export function ProviderMark({
  providerKey,
  mark,
  color,
  size = 40,
}: {
  providerKey?: string
  mark: string
  color: string
  size?: number
}) {
  const [logoFailed, setLogoFailed] = useState(false)
  const showLogo = providerKey != null && !logoFailed

  return (
    <div
      className="ring-border/60 flex flex-none items-center justify-center rounded-lg font-bold text-white ring-1"
      style={{ width: size, height: size, backgroundColor: color, fontSize: size * 0.3 }}
      aria-hidden="true"
    >
      {showLogo ? (
        <img
          src={`/integrations/${providerKey}.svg`}
          alt=""
          style={{ width: size * 0.55, height: size * 0.55 }}
          onError={() => setLogoFailed(true)}
        />
      ) : (
        mark
      )}
    </div>
  )
}
