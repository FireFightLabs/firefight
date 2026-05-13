import type { CurrentUser, CurrentWorkspace } from './serializers'

export type Flash = {
  notice?: string
  alert?: string
}

export type SharedProps = {
  flash: Flash
  currentUser?: CurrentUser
  currentWorkspace?: CurrentWorkspace
}

export interface Pagination {
  page: number
  perPage: number
  totalCount: number
  totalPages: number
}
