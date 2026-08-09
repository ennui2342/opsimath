module Ui
  class BadgeComponentPreview < ViewComponent::Preview
    def default
      render(BadgeComponent.new(text: "Science fiction"))
    end

    def conflict
      render(BadgeComponent.new(text: "enrichment_conflict", variant: :conflict))
    end

    def success
      render(BadgeComponent.new(text: "accepted", variant: :success))
    end
  end
end
