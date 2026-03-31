import type { AttributeType } from "@/modules/catalogue/types"

export const ATTRIBUTE_TYPE_LABELS: Record<AttributeType, string> = {
  text: "Text",
  number: "Number",
  boolean: "Boolean",
  select: "Select",
  reference: "Reference",
  list: "List",
  slack_channel: "Slack Channel",
  workspace_member: "Member",
  workspace_members: "Members",
}

export const ATTRIBUTE_TYPES: AttributeType[] = [
  "text",
  "number",
  "boolean",
  "select",
  "reference",
  "list",
  "slack_channel",
  "workspace_member",
  "workspace_members",
]
