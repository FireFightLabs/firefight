# What a run's trigger data holds for something that happened, and the flat fields its trigger's conditions read. An
# incident's events hand on the incident, its follow up and who did it in the shapes outbound webhooks send them, so a
# workflow reads them the way every integration already does. The fields a condition reads are strings
# (Policy::Conditions) named by Workflow::Trigger::Fields, and a field that names a catalog entry (service, team) brings
# that entry's related entries and attributes along (Policy::ContextBuilder).
class Workflow::TriggerPayloads
  Built = Data.define(:payload, :context, :tags)

  F = Workflow::Trigger::Fields
  KEY_CHANGE = F::CHANGE
  KEY_EVENT = "event".freeze
  POSTMORTEM_EVENTS = [ IncidentEvent::POSTMORTEM_STARTED, IncidentEvent::POSTMORTEM_GENERATED, IncidentEvent::POSTMORTEM_EDITED ].freeze

  def initialize(workspace)
    @workspace = workspace
  end

  def build(kind, subject, details)
    case kind
    when Workflow::Trigger::KIND_INCIDENT_DECLARED, Workflow::Trigger::KIND_INCIDENT_CHANGED, Workflow::Trigger::KIND_FOLLOW_UP_CHANGED
      incident_event(subject, details)
    when Workflow::Trigger::KIND_ALERT_RECEIVED then alert(subject, details)
    when Workflow::Trigger::KIND_NOTICE_RAISED then notice(subject, details)
    when Workflow::Trigger::KIND_INVESTIGATION_FINISHED then investigation(subject)
    when Workflow::Trigger::KIND_RUN_FAILED then run_failed(subject)
    when Workflow::Trigger::KIND_DEPLOY_FINISHED then run_ended(subject, details)
    when Workflow::Trigger::KIND_RESOURCE_CHANGED then resource_changed(subject)
    when Workflow::Trigger::KIND_SECURITY_EVENT then security_event(details)
    when Workflow::Trigger::KIND_ISSUE_ASSIGNED then issue_assigned(subject, details)
    when Workflow::Trigger::KIND_INBOUND_WEBHOOK then webhook(details)
    else raise ArgumentError, "#{kind} is not a kind of trigger something happening starts"
    end
  end

  private

  def tags_of(details) = Array(details["tags"]).map(&:to_s)

  # The incident as outbound webhooks send it, who did it, each named field's value before and after, and the follow
  # up or postmortem the event is about.
  def incident_event(event, details)
    tags = tags_of(details)
    incident = event.incident
    payload = {
      KEY_EVENT => event.event_type, KEY_CHANGE => tags, "incident" => incident_summary(incident),
      "actor" => event.actor && rendered("webhooks/shared/actor", actor: event.actor), "changes" => before_and_after(event)
    }
    action = event.eventable.try(:incident_action)
    payload["action"] = rendered("webhooks/shared/action", action: action) if action
    payload["postmortem"] = incident.postmortem.slice("id", "title", "status") if POSTMORTEM_EVENTS.include?(event.event_type) && incident.postmortem
    context = incident_context(incident).merge(KEY_CHANGE => tags.join(", "))
    Built.new(payload: payload.compact, context: context, tags: tags)
  end


  def before_and_after(event)
    current = event.eventable
    return {} unless current.is_a?(IncidentUpdate)

    previous = IncidentUpdate.where(incident_id: current.incident_id).where(created_at: ...current.created_at).order(created_at: :desc).first
    Array(current.changed_fields).to_h do |field|
      [ field, { "before" => field_value(previous, field), "after" => field_value(current, field) } ]
    end
  end

  def field_value(update, field)
    return nil unless update

    association = Workflow::Trigger::Changes::NAMED_COLUMNS[field]
    return update.public_send(association)&.then { |record| record.try(:name) || record.try(:actor_display_name) } if association

    update.has_attribute?(field) ? update[field] : nil
  end

  def rendered(partial, **locals)
    JSON.parse(Webhooks::PayloadRenderer.renderer.render(partial: partial, locals: locals, formats: [ :json ]))
  end

  def incident_context(incident)
    fields = {
      F::SEVERITY => incident.incident_severity&.slug, F::TYPE => incident.incident_type&.slug, F::STATUS => incident.incident_status&.slug,
      F::STAGE => incident.incident_status&.incident_lifecycle_stage&.key, F::SOURCE => incident.source, F::PRIVATE => incident.is_private.to_s,
      F::TEST => incident.is_test.to_s, F::LEAD => incident.lead&.try(:email)
    }
    incident.custom_fields_for_display.each { |slug, value| fields["#{F::CUSTOM_FIELD_PREFIX}#{slug}"] = Array(value).join(", ") }
    Policy::ContextBuilder.build(workspace: @workspace, fields: fields)
  end

  def incident_summary(incident)
    incident && rendered("webhooks/shared/incident", incident: incident)
  end

  def alert(alert, details)
    outcome = details[F::OUTCOME].to_s
    fields = alert.fields.to_h.slice(*AlertProviders::Base::NORMALIZED_FIELDS)
    payload = {
      "alert" => fields.merge("id" => alert.id, "title" => alert.title, "status" => alert.status, "url" => alert.source_url,
                              "source" => alert.alert_source.name, "provider" => alert.alert_source.provider, "event_count" => alert.event_count,
                              "received_at" => alert.received_at&.utc&.iso8601),
      "outcome" => outcome, "incident" => incident_summary(alert.incident)
    }
    context = fields.merge(F::TITLE => alert.title, F::STATUS => alert.status, F::SOURCE => alert.alert_source.name,
                           "provider" => alert.alert_source.provider, F::OUTCOME => outcome)
    Built.new(payload: payload, context: Policy::ContextBuilder.build(workspace: @workspace, fields: context), tags: [])
  end

  def notice(notice, details)
    change = details[KEY_CHANGE].to_s
    payload = {
      KEY_CHANGE => change,
      "notice" => { "id" => notice.id, "signal" => notice.signal, "topic" => notice.topic, "summary" => notice.summary, "severity" => notice.severity,
                    "due_on" => notice.due_on&.iso8601, "resource" => notice.resource&.name, "times_said" => notice.times_said }
    }
    context = { KEY_CHANGE => change, F::SIGNAL => notice.signal, F::SEVERITY => notice.severity, F::TOPIC => notice.topic, F::RESOURCE => notice.resource&.name }
    Built.new(payload: payload, context: Policy.normalize_context(context), tags: [])
  end

  def investigation(investigation)
    finding = investigation.finding
    confidence = finding&.winning_hypothesis&.confidence
    payload = {
      "investigation" => {
        "id" => investigation.id, "status" => investigation.status, "question" => investigation.question, "trigger_source" => investigation.trigger_source,
        "url" => AppUrl.absolute(Rails.application.routes.url_helpers.investigation_path(investigation)),
        "finding" => finding&.summary, "confidence" => confidence&.to_f, "suggests_incident" => finding&.suggests_incident || false,
        "error" => investigation.error_summary
      },
      "incident" => incident_summary(investigation.incident)
    }
    context = {
      F::STATUS => investigation.status, F::SUGGESTS_INCIDENT => (finding&.suggests_incident || false).to_s,
      F::TRIGGER_SOURCE => investigation.trigger_source, F::INCIDENT => investigation.incident&.identifier
    }
    Built.new(payload: payload, context: Policy.normalize_context(context), tags: [])
  end

  def run_failed(run)
    failed = run.steps.where(status: Workflow::Run::Step::STATUS_FAILED).order(:finished_at).first
    payload = {
      "run" => { "id" => run.id, "workflow" => run.workflow.name, "workflow_slug" => run.workflow.slug, "trigger_kind" => run.trigger_kind,
                 "error" => run.error, "failed_step" => failed&.name, "url" => Workflow::Links.run(run) }
    }
    context = { F::WORKFLOW => run.workflow.slug, F::TRIGGER_KIND => run.trigger_kind, F::FAILED_STEP => failed&.name }
    Built.new(payload: payload, context: Policy.normalize_context(context), tags: [])
  end

  # A deploy or CI run a connection reported ended, with the connection that told Firefight.
  def run_ended(row, details)
    run = details.to_h.stringify_keys.slice(*RUN_KEYS)
    payload = { "run" => run.merge("connection" => row.integration.name) }
    context = { F::KIND => run["kind"], F::OUTCOME => run["outcome"], F::PROVIDER => run["provider"], F::PLACE => run["place"], F::REF => run["ref"],
                F::ENVIRONMENT => run["environment"], F::NAME => run["name"] }
    Built.new(payload: payload, context: Policy.normalize_context(context), tags: [])
  end

  RUN_KEYS = %w[kind outcome provider reference name place ref commit url environment].freeze

  def resource_changed(change)
    resource = change.resource
    payload = {
      "change" => { "kind" => change.kind, "from" => change.from_value, "to" => change.to_value, "detail" => change.detail, "words" => change.words,
                    "happened_at" => change.happened_at&.utc&.iso8601 },
      "resource" => { "id" => resource.id, "name" => resource.name, "kind" => resource.kind, "provider" => resource.provider, "account" => resource.account,
                      "status" => resource.status, "url" => resource.url }
    }
    context = { F::CHANGE => change.kind, F::KIND => resource.kind, F::PROVIDER => resource.provider, F::NAME => resource.name, F::DETAIL => change.detail }
    Built.new(payload: payload, context: Policy.normalize_context(context), tags: [])
  end

  SECURITY_KEYS = %w[kind provider reference place what url public].freeze

  def security_event(details)
    event = details.to_h.stringify_keys.slice(*SECURITY_KEYS)
    context = { F::KIND => event["kind"], F::PROVIDER => event["provider"], F::PLACE => event["place"], F::PUBLIC => event["public"].to_s }
    Built.new(payload: { "event" => event }, context: Policy.normalize_context(context), tags: [])
  end

  ISSUE_KEYS = %w[provider key title url text asked_by asked_by_email].freeze

  def issue_assigned(row, details)
    issue = details.to_h.stringify_keys.slice(*ISSUE_KEYS).merge("connection" => row.integration.name)
    context = { F::PROVIDER => issue["provider"], F::TITLE => issue["title"], F::ASKED_BY => issue["asked_by_email"] }
    Built.new(payload: { "issue" => issue }, context: Policy.normalize_context(context), tags: [])
  end

  # A body's fields as conditions read them, body.<path>, as deep as BODY_DEPTH, a list's items by their place.
  BODY_DEPTH = 4

  def webhook(details)
    body = details["body"]
    context = {}
    flatten(body, F::BODY_PREFIX.delete_suffix("."), context, 0)
    payload = { "body" => body, "received_at" => details["received_at"], "delivery" => details["delivery"] }
    Built.new(payload: payload, context: Policy.normalize_context(context), tags: [])
  end

  def flatten(value, path, into, depth)
    case value
    when Hash
      value.each { |key, inner| flatten(inner, "#{path}.#{key}", into, depth + 1) } if depth < BODY_DEPTH
    when Array
      value.each_with_index { |inner, index| flatten(inner, "#{path}.#{index}", into, depth + 1) } if depth < BODY_DEPTH
    else
      into[path] = value
    end
  end
end
