// A choice the server lists with its words, such as a kind of check, so no label is kept twice.
export interface CheckChoice {
  value: string
  label: string
  description?: string
}

// Which connected providers Halon can read spend from, and which it cannot.
export interface SpendCoverage {
  read: string[]
  unread: string[]
  // Every provider Halon can read spend from once connected.
  offered: string[]
}
