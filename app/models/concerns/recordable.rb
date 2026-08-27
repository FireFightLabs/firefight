module Recordable
  extend ActiveSupport::Concern

  included do
    has_one :incident_event, as: :eventable, touch: true
  end

  class_methods do
    def records(source_class, recorder:)
      @recorded_source = source_class
      @recorder_attr   = recorder
    end

    def recorded_source
      @recorded_source
    end

    def recorder_attr
      @recorder_attr
    end
  end
end
