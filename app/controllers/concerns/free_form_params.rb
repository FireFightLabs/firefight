# A free form object in a request, such as a tool's arguments or a watch, which the model checks rather than the
# controller permitting it key by key.
module FreeFormParams
  private

  def object_param(value) = value.is_a?(ActionController::Parameters) ? value.to_unsafe_h : nil
end
