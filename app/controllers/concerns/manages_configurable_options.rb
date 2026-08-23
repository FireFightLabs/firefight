# The seven actions every configurable option list needs. Guard rules come from
# the model's *_blocked_reason methods, so a controller only supplies its model,
# its settings path, and any attributes specific to it.
module ManagesConfigurableOptions
  extend ActiveSupport::Concern

  included do
    before_action :require_authentication
    before_action :require_admin!
    before_action :set_option, only: [ :update, :disable, :enable, :destroy, :make_default ]
  end

  def create
    name = params[:name].to_s.strip
    option = option_scope.new(
      name: name,
      description: params[:description],
      **color_attribute,
      **create_attributes
    )

    option.save_in_position!
    renumber!
    redirect_to options_path, notice: "#{option.name} was created."
  rescue ActiveRecord::RecordInvalid => e
    redirect_back fallback_location: options_path, inertia: { errors: e.record.errors.to_hash }
  end

  # Renaming leaves the slug alone. It is the stable handle other code and
  # stored records refer to.
  def update
    attrs = { name: params[:name], description: params[:description], color: params[:color] }.compact
    attrs.delete(:color) unless option_model.colored?

    if @option.update(attrs)
      redirect_to options_path, notice: "#{@option.name} was updated."
    else
      redirect_back fallback_location: options_path, inertia: { errors: @option.errors.to_hash }
    end
  end

  def disable
    return redirect_blocked(@option.disable_blocked_reason) if @option.disable_blocked_reason

    @option.update!(deleted_at: Time.current)
    redirect_to options_path, notice: "#{@option.name} was disabled."
  end

  def enable
    @option.update!(deleted_at: nil)
    redirect_to options_path, notice: "#{@option.name} was enabled."
  end

  def make_default
    return redirect_blocked(@option.default_blocked_reason) if @option.default_blocked_reason

    @option.make_default!
    redirect_to options_path, notice: "#{@option.name} is now the default #{noun}."
  end

  def destroy
    return redirect_blocked(@option.deletion_blocked_reason) if @option.deletion_blocked_reason

    @option.destroy!
    renumber!
    redirect_to options_path, notice: "#{@option.name} was deleted."
  end

  def reorder
    option_model.reorder!(current_workspace, params.require(:ordered_ids))
    redirect_to options_path, notice: "#{noun.capitalize} order updated."
  end

  private

  DEFAULT_COLOR = "#6B7280".freeze

  def option_model
    raise NotImplementedError
  end

  def options_path
    raise NotImplementedError
  end

  # Attributes beyond the shared ones, for models that need more.
  def create_attributes
    {}
  end

  def color_attribute
    return {} unless option_model.colored?

    { color: params[:color].presence || DEFAULT_COLOR }
  end

  def noun
    option_model::NOUN
  end

  def option_scope
    option_model.where(workspace_id: current_workspace.id)
  end

  def set_option
    @option = option_scope.find(params[:id])
  end

  def redirect_blocked(reason)
    redirect_to options_path, alert: reason
  end

  # Closes the gaps a create or destroy leaves, and re-derives any column
  # mirrored from the order.
  def renumber!
    option_model.reorder!(current_workspace, option_scope.ordered.pluck(:id))
  end
end
