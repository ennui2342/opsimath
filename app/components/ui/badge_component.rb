module Ui
  # A small labeled pill — genre/subject/tag/literary_form on the book
  # page, kind/status on the PendingDecision review queue. See
  # docs/UI_PRINCIPLES.md principles 5/6 (ViewComponent, named theme
  # tokens) for why this exists as its own component rather than a
  # copy-pasted <span> per view.
  class BadgeComponent < ApplicationComponent
    VARIANTS = {
      default: "bg-gray-100 text-gray-800 dark:bg-gray-800 dark:text-gray-200",
      conflict: "bg-conflict-100 text-conflict-800 dark:bg-conflict-900 dark:text-conflict-200",
      success: "bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-200",
      # Added 2026-09-04 so "Read" (a reading fact) no longer shares a
      # color with "Owned" (an ownership fact) — the two used to both be
      # :success and were easy to misread as duplicates sitting side by
      # side on an edition card. :info also covers any other "settled,
      # positive" status that isn't specifically an ownership one.
      info: "bg-blue-100 text-blue-800 dark:bg-blue-900 dark:text-blue-200",
      # "Reading" (in progress) — distinct from :default's neutral gray,
      # which stays for DNF/TBR (nothing currently happening).
      accent: "bg-purple-100 text-purple-800 dark:bg-purple-900 dark:text-purple-200"
    }.freeze

    def initialize(text:, variant: :default)
      @text = text
      @variant = VARIANTS.key?(variant) ? variant : :default
    end

    def call
      tag.span(@text, class: "inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-medium #{VARIANTS.fetch(@variant)}")
    end
  end
end
