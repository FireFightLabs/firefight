export const RISK_VARIANT: Record<string, "default" | "secondary" | "destructive" | "outline"> = {
  read: "secondary",
  write: "default",
  destructive: "destructive",
}

export const IMPLICIT_AUTHORITY: Record<string, string | null> = {
  admin:
    "Admins hold every catalogued ability without a grant, because enabling a capability is itself the deliberate decision. Approval policies still gate the risky ones.",
  member:
    "Members read Firefight's own data, including the resource map in every environment, and take part in incidents without a grant, whether from Slack, the API, or MCP. A grant of map.read below limits the map to the environments it names. Configuring the workspace and anything that reaches another system needs one of the grants below.",
  none: null,
}
