module Ui
  class FieldDiffComponentPreview < ViewComponent::Preview
    def default
      render(FieldDiffComponent.new(field: :publisher, current: "St Martins Pr", proposed: "HarperVoyager (UK)", source: "isfdb"))
    end

    def blank_current
      render(FieldDiffComponent.new(field: :language, current: nil, proposed: "eng", source: "isfdb"))
    end

    def no_source
      render(FieldDiffComponent.new(field: :publish_date, current: "2011", proposed: "2016-12"))
    end
  end
end
