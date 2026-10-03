module Operator
  # A model a regression run can be told to use.
  class HalonRegressionModelSerializer < BaseSerializer
    object_as :model

    type :string
    def id = model.id

    type :string
    def name = model.name

    type :string
    def provider = model.provider
  end
end
