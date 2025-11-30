export enum Platform {
  Slack = 'slack',
  Teams = 'teams',
}

export enum Role {
  Member = 'member',
  Admin = 'admin',
  Owner = 'owner',
}

export interface User {
  id: string
  email: string
  name: string
  avatar_url?: string
}

export interface Workspace {
  id: string
  platform: Platform
  name: string
  avatar_url?: string
}

export interface WorkspaceMembership {
  id: string
  role: Role
  user: User
  workspace: Workspace
}
