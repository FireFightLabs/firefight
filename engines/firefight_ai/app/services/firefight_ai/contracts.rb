module FirefightAi
  # The reasoning behind an investigation gets replaced as models change, the records it
  # writes do not. Each contract is a fixed shape with a swappable implementation.
  module Contracts
    class NoImplementation < StandardError; end

    PLANNER = :planner
    BRANCH_RUNNER = :branch_runner
    SPECIALIST = :specialist
    CONFIDENCE_SCORER = :confidence_scorer
    MATCHER = :matcher
    ALL = [ PLANNER, BRANCH_RUNNER, SPECIALIST, CONFIDENCE_SCORER, MATCHER ].freeze

    def self.use(contract, implementation)
      registry[known!(contract)] = implementation
    end

    def self.resolve(contract)
      implementation = registry[known!(contract)]
      raise NoImplementation, "No implementation registered for #{contract}" if implementation.nil?

      implementation.is_a?(String) ? implementation.constantize : implementation
    end

    def self.registered?(contract)
      !registry[known!(contract)].nil?
    end

    def self.reset!
      @registry = {}
    end

    def self.registry
      @registry ||= {}
    end
    private_class_method :registry

    def self.known!(contract)
      name = contract.to_sym
      raise ArgumentError, "Unknown contract #{contract.inspect}" unless ALL.include?(name)

      name
    end
    private_class_method :known!
  end
end
