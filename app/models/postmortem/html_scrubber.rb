# The editor's safe list. A task list is saved as data attributes and a checkbox, so those are kept only on the element
# and with the values the editor writes, and a checkbox only inside a task item.
class Postmortem::HtmlScrubber < Rails::HTML::PermitScrubber
  TAGS = %w[
    p br hr h1 h2 h3 h4 h5 h6 strong em u s del code pre blockquote
    ul ol li a span div
    table thead tbody tr th td
    label input
  ].freeze
  ATTRIBUTES = %w[href title class colspan rowspan target rel].freeze
  CHECKBOX_TAG = "input"
  TASK_LIST_ATTRIBUTES = {
    "ul" => { "data-type" => %w[taskList] },
    "li" => { "data-type" => %w[taskItem], "data-checked" => %w[true false] },
    CHECKBOX_TAG => { "type" => %w[checkbox], "checked" => [ "", "checked" ] }
  }.freeze
  TASK_LIST_ATTRIBUTE_NAMES = TASK_LIST_ATTRIBUTES.values.flat_map(&:keys).uniq.freeze

  def initialize
    super
    self.tags = TAGS
    self.attributes = ATTRIBUTES + TASK_LIST_ATTRIBUTE_NAMES
  end

  protected

  def allowed_node?(node)
    super && (node.name != CHECKBOX_TAG || task_checkbox?(node))
  end

  # A checkbox keeps its type and tick and nothing else.
  def scrub_attributes(node)
    node.attribute_nodes.each do |attribute|
      next unless node.name == CHECKBOX_TAG || TASK_LIST_ATTRIBUTE_NAMES.include?(attribute.name)

      attribute.remove unless TASK_LIST_ATTRIBUTES.dig(node.name, attribute.name)&.include?(attribute.value)
    end
    super
  end

  private

  def task_checkbox?(node)
    node["type"] == "checkbox" && node.ancestors("li").first&.[]("data-type") == "taskItem"
  end
end
