export const RISK_VARIANT: Record<string, "default" | "secondary" | "destructive" | "outline"> = {
  read: "secondary",
  write: "default",
  destructive: "destructive",
}

export const IMPLICIT_AUTHORITY: Record<string, string | null> = {
  admin:
    "Admins hold every catalogued ability without a grant, every connected tool included. Approval policies still gate the risky ones.",
  member:
    "Members read Firefight's own data, including the resource map in every environment, read every connected tool, take part in incidents, and ask Halon or start investigations without a grant, whether from Slack, the dashboard, the API, or MCP. A grant of map.read limits the map to the environments it names, a grant of investigations.create decides who may ask, and a grant of a connection's reads, alone or in a pack, decides where they read it. No access below takes any of these away at once, and Restore gives it back. Configuring the workspace and any tool that changes something needs one of the grants below, such as a connection's changes pack.",
  none: null,
}
