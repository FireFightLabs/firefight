# frozen_string_literal: true

# Recordable is the partner concern to Trackable. It's included on the
# immutable snapshot models (IncidentUpdate, IncidentActionUpdate,
# PostmortemUpdate) — one row per `record_change!` on the live model.
#
#   class IncidentUpdate < ApplicationRecord
#     include Recordable
#     records Incident, recorder: :created_by
#   end
#
# `recorder:` names the belongs_to column that stores *who* performed the
# change (different per recordable for historical reasons — IncidentUpdate
# uses `created_by`, IncidentActionUpdate uses `actor`, PostmortemUpdate
# uses `edited_by`).
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
