import { User, Workspace } from './models'

export type Flash = {
  notice?: string
  alert?: string
}

export type SharedProps = {
  flash: Flash
  currentUser?: User
  currentWorkspace?: Workspace
}
