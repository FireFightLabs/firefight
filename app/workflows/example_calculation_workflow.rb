# frozen_string_literal: true

# ExampleCalculationWorkflow - Demo workflow showing input/output flow and parallel execution
#
# This workflow demonstrates:
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
class ExampleCalculationWorkflow < Workflows::Base
  workflow_name "example.calculation.v1"

  # Step 1: Fetch numbers (either from context or generate them)
  step :fetch_numbers

  # Step 2 & 3: Run in parallel (both depend on fetch_numbers)
  step :calculate_sum, depends_on: [:fetch_numbers]
  step :calculate_product, depends_on: [:fetch_numbers]

  # Step 4: Combine results (waits for both calculations to complete)
  step :combine_results, depends_on: [:calculate_sum, :calculate_product]

  # Step 5: Store final result
  step :store_result, depends_on: [:combine_results]

  # Fetch or generate numbers to process
  def fetch_numbers(workflow:, step:, input:)
    numbers = workflow.context["numbers"] || (1..10).to_a

    Rails.logger.info(
      :workflow_step_fetch_numbers,
      workflow_id: workflow.id,
      numbers: numbers,
      count: numbers.size
    )

    { numbers: numbers, count: numbers.size }
  end

  # Calculate sum of numbers (runs in parallel with calculate_product)
  def calculate_sum(workflow:, step:, input:)
    numbers = input["fetch_numbers"]["numbers"]
    sum = numbers.sum

    Rails.logger.info(
      :workflow_step_calculate_sum,
      workflow_id: workflow.id,
      numbers: numbers,
      sum: sum
    )

    # Simulate some work
    sleep(0.1)

    { sum: sum, operation: "sum" }
  end

  # Calculate product of numbers (runs in parallel with calculate_sum)
  def calculate_product(workflow:, step:, input:)
    numbers = input["fetch_numbers"]["numbers"]
    product = numbers.reduce(1, :*)

    Rails.logger.info(
      :workflow_step_calculate_product,
      workflow_id: workflow.id,
      numbers: numbers,
      product: product
    )

    # Simulate some work
    sleep(0.1)

    { product: product, operation: "product" }
  end

  # Combine results from both calculations
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

    Rails.logger.info(
      :workflow_step_combine_results,
      workflow_id: workflow.id,
      result: result
    )

    result
  end

  # Store final result (just in step output, no database writes)
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

    Rails.logger.info(
      :workflow_step_store_result,
      workflow_id: workflow.id,
      subject_id: workflow.subject_id,
      result: result
    )

    result
  end
end
