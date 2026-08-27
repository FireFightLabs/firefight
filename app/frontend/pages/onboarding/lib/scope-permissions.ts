export type Scope = {
  name: string;
  explanation: string;
  boundary?: string;
};

export type PermissionGroup = {
  title: string;
  description: string;
  scopes: Scope[];
};

export const PERMISSION_GROUPS: PermissionGroup[] = [
  {
    title: "Sign-in and workspace identity",
    description:
      "Used to confirm who is signing in and which Slack workspace they belong to.",
    scopes: [
      {
        name: "openid",
        explanation:
          "Lets Slack verify the user's identity so Firefight can sign them in securely.",
      },
      {
        name: "profile",
        explanation:
          "Provides the user's name and avatar so Firefight can show who is using the workspace.",
      },
      {
        name: "email",
        explanation:
          "Provides the user's email address for account linking and membership checks.",
      },
      {
        name: "users:read",
        explanation:
          "Lets Firefight look up Slack users when matching members, resolving mentions, and showing responder details.",
      },
      {
        name: "users:read.email",
        explanation:
          "Lets Firefight match Slack identities to Firefight accounts by email during sign-in and onboarding.",
        boundary: "Used only for account linking, not for marketing.",
      },
      {
        name: "team:read",
        explanation:
          "Lets Firefight identify the Slack workspace being connected so the install is tied to the correct team.",
      },
    ],
  },
  {
    title: "Incident channels and notifications",
    description:
      "Used to create response spaces, post updates, and help responders coordinate in Slack.",
    scopes: [
      {
        name: "commands",
        explanation:
          "Enables the /firefight and /ff slash commands used to open Firefight workflows from Slack.",
      },
      {
        name: "chat:write",
        explanation:
          "Lets Firefight post incident announcements, status updates, and workflow messages in Slack.",
      },
      {
        name: "chat:write.public",
        explanation:
          "Lets Firefight post to public channels when sharing incident information without requiring the bot to already be in that channel.",
      },
      {
        name: "im:write",
        explanation:
          "Lets Firefight send direct messages for handoffs, sharing, and responder notifications.",
      },
      {
        name: "channels:manage",
        explanation:
          "Lets Firefight create and manage public incident channels during incident setup.",
        boundary: "Only for public incident channels Firefight creates.",
      },
      {
        name: "channels:join",
        explanation:
          "Lets the bot join the public channels it creates so it can post updates and respond to commands there.",
      },
      {
        name: "channels:read",
        explanation:
          "Lets Firefight look up public channel information when checking for incident channels and existing setup.",
      },
      {
        name: "groups:write",
        explanation:
          "Lets Firefight create and manage private incident channels when a workspace wants private response spaces.",
        boundary: "Only for private incident channels Firefight creates.",
      },
      {
        name: "app_mentions:read",
        explanation:
          "Lets Firefight respond when someone mentions the app in Slack during incident response.",
      },
    ],
  },
  {
    title: "Incident timeline and context",
    description:
      "Used to assemble timelines, capture important activity, and include relevant shared material in incident records.",
    scopes: [
      {
        name: "channels:history",
        explanation:
          "Lets Firefight read message history to build timelines and capture key updates.",
        boundary: "Only in public incident channels Firefight is invited to.",
      },
      {
        name: "groups:history",
        explanation:
          "Lets Firefight read message history for the same timeline and update workflows.",
        boundary: "Only in private incident channels Firefight is invited to.",
      },
      {
        name: "files:read",
        explanation:
          "Lets Firefight access files shared in incident conversations when those files need to be referenced or archived with incident context.",
      },
    ],
  },
  {
    title: "Lightweight workflow actions",
    description:
      "Used for smaller Slack interactions that help teams coordinate without leaving the channel.",
    scopes: [
      {
        name: "pins:write",
        explanation:
          "Lets Firefight pin important incident messages so responders can quickly find the current source of truth.",
      },
      {
        name: "pins:read",
        explanation:
          "Lets Firefight track pin changes so pinned messages stay reflected in the incident timeline.",
      },
      {
        name: "reactions:read",
        explanation:
          "Lets Firefight react to emoji-based workflows, such as turning a reaction into an action item or follow-up.",
      },
      {
        name: "reactions:write",
        explanation:
          "Lets Firefight add reactions when acknowledging or updating workflow state in Slack.",
      },
    ],
  },
];

export const TOTAL_SCOPES = PERMISSION_GROUPS.reduce(
  (sum, group) => sum + group.scopes.length,
  0,
);
