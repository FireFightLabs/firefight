module Operator
  # Places a workflow's steps for drawing. A step's column is the length of its longest dependency chain, so steps that
  # can run together share a column and every edge points right.
  class WorkflowGraph
    Node = Data.define(:step, :column, :row)

    def initialize(steps)
      @steps = steps.to_a
      @by_name = @steps.index_by(&:name)
    end

    def nodes
      rows = Hash.new(0)
      @steps.sort_by(&:position).map do |step|
        column = depth(step.name)
        node = Node.new(step, column, rows[column])
        rows[column] += 1
        node
      end
    end

    private

    def depth(name, seen = Set.new)
      return 0 if seen.include?(name)

      deps = Array(@by_name[name]&.depends_on).select { |dependency| @by_name.key?(dependency) }
      return 0 if deps.empty?

      1 + deps.map { |dependency| depth(dependency, seen | [ name ]) }.max
    end
  end
end
