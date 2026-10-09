export interface ConfigurableOption {
  id: string
  name: string
  color?: string | null
  enabled: boolean
  isDefault?: boolean
  deletionBlockedReason?: string
  disableBlockedReason?: string
  defaultBlockedReason?: string
}
