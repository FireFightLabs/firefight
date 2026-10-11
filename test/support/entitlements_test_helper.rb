module EntitlementsTestHelper
  extend ActiveSupport::Concern

  included do
    teardown { Entitlements.reset_backend! }
  end

  # Denies features while still letting the workspace in, the way a lapsed trial loses AI but keeps its data.
  DenyingBackend = Struct.new(:message) do
    def check(_workspace, feature)
      feature == Entitlements::ACCESS ? Entitlements.allow : Entitlements.deny(message)
    end
  end

  # Keeps the workspace out altogether, as a hosted build does once a subscription has lapsed.
  AccessBlockingBackend = Struct.new(:message, :path) do
    def check(_workspace, feature)
      feature == Entitlements::ACCESS ? Entitlements.deny(message, path: path) : Entitlements.allow
    end
  end

  # Allows everything and names where a new workspace goes next, as a hosted build's plan picker does.
  NextStepBackend = Struct.new(:path) do
    def check(_workspace, _feature) = Entitlements.allow
    def next_step_path(_workspace) = path
  end

  # Sends only a workspace without a plan on to choose one, as a hosted build's plan picker does once a workspace pays.
  PlanPickerBackend = Struct.new(:path, :subscribed_ids) do
    def check(_workspace, _feature) = Entitlements.allow
    def next_step_path(workspace) = subscribed_ids.include?(workspace.id) ? nil : path
  end

  # Sells one plan the way a hosted build does. A workspace without one is closed until setup starts it, and one whose
  # plan lapsed stays open to read while new incidents and AI stop. stage is :none, :active or :lapsed.
  class PlanBackend
    NO_PLAN = "This workspace does not have a plan yet.".freeze
    LAPSED = "Halon and new incidents are paused because the plan ended.".freeze

    attr_accessor :stage

    def initialize(path, stage)
      @path = path
      @stage = stage
    end

    def check(_workspace, feature)
      case stage
      when :none then Entitlements.deny(NO_PLAN, path: @path)
      when :lapsed then [ Entitlements::AI, Entitlements::INCIDENTS ].include?(feature) ? Entitlements.deny(LAPSED, path: @path) : Entitlements.allow
      else Entitlements.allow
      end
    end

    def plan(_workspace)
      Entitlements::Plan.new(
        active: stage == :active, price: "$99", price_note: "Early adopter price", included: [ "Every feature" ],
        trial_days: 14, terms: "Free for 14 days.", summary: (stage == :active ? "Your trial runs until October 25, 2026." : nil),
        start_path: @path, start_blocked_reason: nil
      )
    end
  end

  def sell_plan!(stage: :none, path: "/plan/checkout")
    Entitlements.backend = PlanBackend.new(path, stage)
  end

  def deny_entitlements!(message = "Your trial has ended.")
    Entitlements.backend = DenyingBackend.new(message)
    message
  end

  def block_access!(message = "This workspace has no plan.", path: nil)
    Entitlements.backend = AccessBlockingBackend.new(message, path)
    message
  end

  def send_new_workspaces_to!(path)
    Entitlements.backend = NextStepBackend.new(path)
  end

  def send_unpaid_workspaces_to!(path, subscribed: [])
    Entitlements.backend = PlanPickerBackend.new(path, subscribed.map(&:id))
  end
end
