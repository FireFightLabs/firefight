module SolidWorkflow
  class Step < Record
    # How a step of a defined workflow decides it may run. Each edge into it is live when the step it leaves took the
    # edge's route, dead when that step took another route, failed or was bypassed, and open while that step has not
    # finished. A step runs once every edge in is settled and one is live, and is bypassed when every edge in is dead.
    # A join of the first route runs as soon as one edge in is live.
    module Routing
      extend ActiveSupport::Concern

      # A step from a definition rather than a Ruby class.
      def graph? = kind.present?

      def join_first?
        kind == SolidWorkflow::Definition::KIND_JOIN && config.to_h["mode"] == SolidWorkflow::Definition::JOIN_FIRST
      end

      def routes_open?(step_map)
        edges = incoming_edges
        return true if edges.empty?
        return edges.any? { |edge| edge_live?(edge, step_map) } if join_first?

        edges.all? { |edge| edge_settled?(edge, step_map) } && edges.any? { |edge| edge_live?(edge, step_map) }
      end

      def unreachable?(step_map)
        edges = incoming_edges
        edges.any? && edges.all? { |edge| edge_settled?(edge, step_map) } && edges.none? { |edge| edge_live?(edge, step_map) }
      end

      # The steps whose edges into this one are live, which is what a join hands on.
      def live_sources(step_map) = incoming_edges.select { |edge| edge_live?(edge, step_map) }.map { |edge| step_map[edge["from"]] }

      # Whether an edge leaving this step carries on, given the route it took.
      def carries_on?(route_name)
        if route_name == SolidWorkflow::Definition::ROUTE_ERROR
          failed? && on_failure == SolidWorkflow::Definition::ON_FAILURE_ERROR_ROUTE
        elsif route_name.present?
          succeeded? && route == route_name
        else
          succeeded? || skipped? || (failed? && on_failure == SolidWorkflow::Definition::ON_FAILURE_CONTINUE)
        end
      end

      private

      def incoming_edges = Array(incoming)

      def edge_settled?(edge, step_map)
        source = step_map[edge["from"]]
        source.nil? || source.completed?
      end

      def edge_live?(edge, step_map)
        source = step_map[edge["from"]]
        source.present? && source.carries_on?(edge["route"])
      end
    end
  end
end
