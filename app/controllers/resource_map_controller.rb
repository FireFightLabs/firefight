# The resource map page: what runs where, read off the connections, and the links people add or confirm on it.
class ResourceMapController < InertiaController
  authorizes Ability::Action::RESOURCE_MAP, read: %i[index checks run_check log_lines changes]
  authorizes Ability::Action::RESOURCE_INTEGRATIONS, update: %i[sync]
  authorizes Ability::Action::RESOURCE_CATALOG,
    update: %i[create_link destroy_link confirm_link dismiss_link link_entry unlink_entry]

  def index
    view = ResourceMap::View.new(current_workspace, current_membership)

    render inertia: "map/index", props: {
      resources: ResourceMapResourceSerializer.many(view.rows),
      links: ResourceMapLinkSerializer.many(view.links),
      connections: ResourceMapConnectionSerializer.many(view.connections),
      changes: ResourceMapChangeSerializer.many(view.changes),
      readsIn: view.environments && current_workspace.environment_entries.where(id: view.environments).pluck(:name),
      catalogEntries: ResourceMapEntrySerializer.many(current_workspace.catalog_entries.active.includes(:catalog_type, outgoing_relationships: { target_entry: :catalog_type }).order(:name))
    }
  end

  # A resource's key checks, read when its panel opens, since whether each can run is worked out live.
  def checks
    target = resource(params[:id])
    render json: { checks: ResourceMapCheckSerializer.many(ResourceMap::KeyQueries.listed(target, current_membership)),
                   none: ResourceMap::KeyQueries.none_reason(target.kind) }
  end

  # Runs one check as the person, through the gateway as the provider tool it reads with, and answers inline.
  def run_check
    target = resource(params[:id])
    check = ResourceMap::KeyQueries.find(target.kind, params[:check])
    return render(json: { outcome: { refusal: ResourceMap::KeyQueries.unknown(target, params[:check]) } }, status: :unprocessable_entity) unless check

    outcome = ResourceMap::KeyQueryRun.call(target, check, principal: current_membership, approval_id: params[:approval_id].presence)
    render json: { outcome: ResourceMapCheckOutcomeSerializer.one(outcome) }
  end

  # The kinds of line a resource usually logs, read when its panel opens, with why none are known when none are.
  def log_lines
    target = resource(params[:id])
    usual = target.log_templates.this_week.most_lines_first
    render json: { lines: ResourceMapLogTemplateSerializer.many(usual.limit(ResourceMap::LogTemplate::SHOWN)), total: usual.count,
                   reason: ResourceMap::LogTemplate.missing_reason(target, current_membership) }
  end

  # What changed around a resource over the last week, read when its panel opens from what Firefight holds. live reads
  # its runs from the provider that runs it as well, as the person, through the gateway as run history.
  def changes
    target = resource(params[:id])
    subject = ResourceMap::Timeline.subject(current_workspace, current_membership, ResourceMap::Timeline::RESOURCE_ARG => target.id)
    timeline = ResourceMap::Timeline.new(workspace: current_workspace, principal: current_membership, subject: subject,
                                         from: ResourceMap::Timeline::PANEL_WINDOW.ago, to: Time.current)
    live, read = params[:live].present? ? ResourceMap::WhatChanged.read_as(timeline, principal: current_membership) : [ [], [] ]
    render json: { entries: ResourceMapTimelineEntrySerializer.many(timeline.entries(live: live)), notes: timeline.notes(read: read),
                   readsRuns: ResourceMap::WhatChanged.targets(timeline).any?, readLive: params[:live].present? }
  end

  def sync
    count = Integrations::MapSweep.queue_for(current_workspace)
    redirect_to resource_map_path, notice: count.positive? ? "Syncing #{count} #{'connection'.pluralize(count)}. The map updates as each one finishes." : "Nothing is connected yet, so there is nothing to sync."
  end

  def create_link
    from = resource(params[:from_id])
    to = resource(params[:to_id])
    link = ResourceMap::Link.add_by_person!(from: from, to: to, relation: params[:relation].to_s, note: params[:note].to_s.strip, by: current_membership)
    return redirect_to(resource_map_path, alert: link) if link.is_a?(String)

    redirect_to resource_map_path, notice: "Added: #{link.sentence}."
  rescue ActiveRecord::RecordInvalid => error
    redirect_to resource_map_path, alert: error.record.errors.full_messages.to_sentence
  end

  def destroy_link
    link = links.find(params[:id])
    reason = link.removal_blocked_reason
    return redirect_to(resource_map_path, alert: reason) if reason

    link.destroy!
    redirect_to resource_map_path, notice: "Removed: #{link.sentence}."
  end

  def confirm_link
    link = links.find(params[:id])
    return redirect_to(resource_map_path, alert: "Someone already decided on this suggestion.") unless link.confirm!(by: current_membership)

    redirect_to resource_map_path, notice: "Confirmed: #{link.sentence}."
  end

  def dismiss_link
    link = links.find(params[:id])
    return redirect_to(resource_map_path, alert: "Someone already decided on this suggestion.") unless link.dismiss!

    redirect_to resource_map_path, notice: "Dismissed: #{link.sentence}. Halon will not suggest it again."
  end

  def link_entry
    target = resource(params[:id])
    entry = current_workspace.catalog_entries.active.find(params[:catalog_entry_id])
    ResourceMap::EntryLink.find_or_create_by!(workspace: current_workspace, catalog_entry: entry, resource: target) { |link| link.added_by = current_membership }
    redirect_to resource_map_path, notice: "#{target.name} now runs #{entry.name}."
  end

  def unlink_entry
    link = ResourceMap::EntryLink.where(workspace: current_workspace, resource_id: visible.select(:id)).find_by!(resource_id: params[:id], catalog_entry_id: params[:entry_id])
    link.destroy!
    redirect_to resource_map_path, notice: "#{link.resource.name} no longer runs #{link.catalog_entry.name}."
  end

  private

  # A write finds only what the person reads on the map, so a resource outside their environments answers as missing.
  def visible = ResourceMap::Resource.visible_to(current_membership, current_workspace)

  def resource(id) = visible.present.find(id)

  def links = ResourceMap::Link.where(workspace: current_workspace, from_resource_id: visible.select(:id), to_resource_id: visible.select(:id))
end
