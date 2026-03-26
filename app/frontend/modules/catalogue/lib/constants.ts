import type { AttributeType } from "@/modules/catalogue/types"

export const ATTRIBUTE_TYPE_LABELS: Record<AttributeType, string> = {
  text: "Text",
  number: "Number",
  boolean: "Boolean",
  select: "Select",
  reference: "Reference",
  list: "List",
}

export const ATTRIBUTE_TYPES: AttributeType[] = [
  "text",
  "number",
  "boolean",
  "select",
  "reference",
  "list",
]
