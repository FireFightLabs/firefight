export interface OperatorPageProps extends Record<string, unknown> {
  operator: { name: string; email: string } | null
}
