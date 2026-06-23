import type { PageProps } from '@inertiajs/core'
import type { CurrentUser, CurrentWorkspace } from '@/types/serializers'

export type FlashData = {
  notice?: string
  alert?: string
  // Custom flash keys sent via `flash.inertia[:key]` on the server.
  api_key_token?: string
}

export type SharedProps = PageProps & {
  currentUser?: CurrentUser
  currentWorkspace?: CurrentWorkspace
  availableWorkspaces?: CurrentWorkspace[]
}

export interface Pagination {
  page: number
  perPage: number
  totalCount: number
  totalPages: number
}
