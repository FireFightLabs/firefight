import type { PageProps } from '@inertiajs/core'
import type { CurrentUser, CurrentWorkspace } from '@/types/serializers'

export type FlashData = {
  notice?: string
  alert?: string
}

export type SharedProps = PageProps & {
  currentUser?: CurrentUser
  currentWorkspace?: CurrentWorkspace
}

export interface Pagination {
  page: number
  perPage: number
  totalCount: number
  totalPages: number
}
