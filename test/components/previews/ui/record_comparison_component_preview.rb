module Ui
  class RecordComparisonComponentPreview < ViewComponent::Preview
    def default
      render(RecordComparisonComponent.new(diffs: [
        { field: "publisher", current: "St Martins Pr", proposed: "HarperVoyager (UK)", source: "isfdb" },
        { field: "publish_date", current: "2011", proposed: "2016-12", source: "isfdb" },
        { field: "page_count", current: nil, proposed: "412", source: "isfdb" }
      ]))
    end
  end
end
