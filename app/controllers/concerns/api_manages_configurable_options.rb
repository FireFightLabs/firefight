# The write half of a configurable option list over REST. The same four
# operations the settings screen and the MCP tools use, calling the same model
# methods, so a list changed here behaves as if it had been dragged.
#
# A controller supplies its model, its gateway resource, and any attributes
# specific to it. Guard rules come from the model's *_blocked_reason methods.
module ApiManagesConfigurableOptions
  extend ActiveSupport::Concern

  included do
    before_action :set_option, only: %i[update destroy]
    helper_method :collection_key
  end

  class_methods do
    def manages_options_as(resource, model)
      define_method(:option_resource) { resource }
      define_method(:option_model) { model }
    end
  end

  # Disabled entries stay out by default, which is the contract this endpoint
  # already had. A caller managing the list asks for them, since re-enabling
  # one means seeing it first.
  def index
    authorize!(option_resource, Ability::Action::ACTION_READ)

    scope = option_model.list_for(current_workspace)
    scope = scope.active unless ActiveModel::Type::Boolean.new.cast(params[:include_disabled])
    @options = scope.ordered

    render "api/v1/options/index"
  end

  def create
    authorize!(option_resource, Ability::Action::ACTION_CREATE)

    ActiveRecord::Base.transaction do
      @option = option_model.create_in_list!(current_workspace, option_attributes)
      apply_state!
    end

    render "api/v1/options/show", status: :created
  end

  def update
    authorize!(option_resource, Ability::Action::ACTION_UPDATE)

    ActiveRecord::Base.transaction do
      @option.update!(option_attributes)
      apply_state!
    end

    @option.reload
    render "api/v1/options/show"
  end

  def destroy
    authorize!(option_resource, Ability::Action::ACTION_DELETE)

    @option.destroy_from_list!
    head :no_content
  end

  # The collection keeps the name it has always had, so adding writes never
  # moves a reader's response shape.
  def collection_key
    controller_name
  end

  private

  # Enabling, disabling and making one the default each have their own rule on
  # the model, so they run as operations rather than as columns on the write.
  def apply_state!
    toggle_enabled! unless params[:enabled].nil?
    make_default! if ActiveModel::Type::Boolean.new.cast(params[:default])
  end

  def toggle_enabled!
    ActiveModel::Type::Boolean.new.cast(params[:enabled]) ? @option.enable! : @option.disable!
  end

  def make_default!
    @option.make_default! if option_model.defaultable?
  end

  # Renaming leaves the slug alone. It is the stable handle stored records
  # refer to.
  def option_attributes
    attributes = { name: params[:name], description: params[:description] }
    attributes[:color] = params[:color] if option_model.colored? && params[:color].present?
    attributes.compact.merge(extra_attributes)
  end

  # Attributes beyond the shared ones, for a list that has some.
  def extra_attributes
    {}
  end

  def set_option
    @option = option_model.list_for(current_workspace).find_by!(slug: params[:id])
  end

  def render_blocked(reason)
    render json: error_response("validation_error", reason), status: :unprocessable_entity
  end
end
