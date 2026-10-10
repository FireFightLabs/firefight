module Operator
  # The sandbox page's figures: what runs now on each provider, what was spent, failovers and rogue ones.
  class SandboxTotalsSerializer < BaseSerializer
    object_as :totals

    type "{ provider: string; name: string; count: number }[]"
    def running = totals.running.map { |provider, count| { provider: provider, name: SandboxProviders.name_of(provider), count: count } }

    type :number
    def today_micros = totals.today_micros

    type :number
    def month_micros = totals.month_micros

    type :number
    def failovers = totals.failovers

    type :number
    def rogue = totals.rogue
  end
end
