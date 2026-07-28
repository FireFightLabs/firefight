// Column tooltips shared across the option settings screens. The wording is the
// same on every list, so it is written once and reworded once.

export const slugColumnHint = (noun: string) =>
  `How this ${noun} is identified in API responses and webhook payloads. Renaming it does not change the slug, so your integrations keep working.`

export const DEFAULT_STATUS_HINT =
  "Every new incident starts in the default status. Only one can be the default at a time, so picking one here unselects it in the other stages."
