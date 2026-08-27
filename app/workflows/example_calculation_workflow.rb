# A demo workflow, kept as a worked example of:
# - Data passing between steps via input/output
# - Parallel step execution (calculate_sum and calculate_product run in parallel)
# - Dependencies (combine_results waits for both calculations)
# - Idempotency helpers
#
# Subject: Any model with a `calculation_result` jsonb field
#
# Usage:
#   workflow = ExampleCalculationWorkflow.start!(subject, context: { numbers: [1, 2, 3, 4, 5] })
#
class ExampleCalculationWorkflow < SolidWorkflow::Base
  workflow_name "example.calculation.v1"

  step :fetch_numbers

  step :calculate_sum, depends_on: [ :fetch_numbers ]
  step :calculate_product, depends_on: [ :fetch_numbers ]

  step :combine_results, depends_on: [ :fetch_numbers, :calculate_sum, :calculate_product ]

  step :store_result, depends_on: [ :combine_results ]

  def fetch_numbers(workflow:, step:, input:)
    numbers = workflow.context["numbers"] || (1..10).to_a

    Rails.logger.info({
      event: "workflow.step.fetch_numbers",
      workflow_id: workflow.id,
      numbers: numbers,
      count: numbers.size
    })

    { numbers: numbers, count: numbers.size }
  end

  def calculate_sum(workflow:, step:, input:)
    numbers = input["fetch_numbers"]["numbers"]
    sum = numbers.sum

    Rails.logger.info({
      event: "workflow.step.calculate_sum",
      workflow_id: workflow.id,
      sum: sum
    })

    # Simulate some work
    sleep(0.1)

    { sum: sum, operation: "sum" }
  end

  def calculate_product(workflow:, step:, input:)
    numbers = input["fetch_numbers"]["numbers"]
    product = numbers.reduce(1, :*)

    Rails.logger.info({
      event: "workflow.step.calculate_product",
      workflow_id: workflow.id,
      product: product
    })

    # Simulate some work
    sleep(0.1)

    { product: product, operation: "product" }
  end

  def combine_results(workflow:, step:, input:)
    sum = input["calculate_sum"]["sum"]
    product = input["calculate_product"]["product"]
    numbers = input["fetch_numbers"]["numbers"]

    result = {
      numbers: numbers,
      sum: sum,
      product: product,
      average: sum.to_f / numbers.size,
      operations_completed: 2
    }

    Rails.logger.info({
      event: "workflow.step.combine_results",
      workflow_id: workflow.id,
      result: result
    })

    result
  end

  # Writes nothing to the database, the result lives in the step output.
  def store_result(workflow:, step:, input:)
    combined = input["combine_results"]

    result = {
      numbers: combined["numbers"],
      sum: combined["sum"],
      product: combined["product"],
      average: combined["average"],
      calculated_at: Time.current.iso8601,
      subject_type: workflow.subject_type,
      subject_id: workflow.subject_id
    }

    Rails.logger.info({
      event: "workflow.step.store_result",
      workflow_id: workflow.id,
      subject_id: workflow.subject_id,
      result: result
    })

    result
  end
end
