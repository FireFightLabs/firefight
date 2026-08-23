class Webhooks::PayloadRenderer
  def self.render(incident_event, delivery_id:)
    template = template_for(incident_event.event_type)

    renderer.render(
      template: template,
      formats: :json,
      layout: false,
      assigns: {
        event: incident_event,
        delivery_id: delivery_id
      }
    ).strip
  end

  def self.template_for(event_type)
    Webhook::SUBSCRIBABLE_EVENT_TEMPLATES.fetch(event_type)
  end

  def self.renderer
    @renderer ||= ApplicationController.renderer.new(https: !Rails.env.local?)
  end
end
