import {
  IconPuzzle,
  IconServer,
  IconUsers,
  IconWorld,
  IconUser,
  IconPlug,
  IconBook,
  IconBox,
} from "@tabler/icons-react"

const iconMap: Record<string, typeof IconServer> = {
  server: IconServer,
  users: IconUsers,
  puzzle: IconPuzzle,
  world: IconWorld,
  user: IconUser,
  plug: IconPlug,
  book: IconBook,
  box: IconBox,
}

export function CatalogIcon({
  iconKey,
  className,
}: {
  iconKey?: string
  className?: string
}) {
  const Icon = (iconKey ? iconMap[iconKey] : undefined) ?? IconBox
  return <Icon className={className} />
}
