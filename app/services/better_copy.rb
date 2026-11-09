# "Want this edition in better condition" — an edition Mark owns (the book page's edition
# panel): the book onto the wishlist hunting exactly that printing — its
# ISFDB publication — so bargain hunting looks for a nicer copy of the
# same edition. (Worded without "copy": the interface talks in editions.) A book already wanted keeps what it's hunting and gains
# this printing; a new want hunts only it. Needs the edition tied to its
# ISFDB printing: without one there's nothing exact to hunt.
class BetterCopy
  class Refused < StandardError; end

  def self.want(work, edition)
    pub = edition.edition_identifiers.find { |i| i.id_type == "isfdb" }&.value&.to_i
    raise Refused, "This edition isn't linked to its ISFDB printing — choose the right printing first." unless pub

    label = CatalogueEvent.edition_label(edition)
    Want.transaction do
      want = work.want
      base = if want.nil? then []
      elsif want.printing_override_ids.nil? then CollectingProfile.current.verdict(want).wanted.map(&:isfdb_pub_id)
      else want.printing_override_ids
      end
      want ||= work.create_want!.tap { |w| WantPrintingsJob.perform_later(w.id) }
      return want if base.include?(pub) && !want.printing_override_ids.nil?

      note = "My #{label} edition, in better condition"
      want.update!(printing_override_ids: base | [ pub ],
                   notes: [ want.notes.presence, (note unless want.notes.to_s.include?(note)) ].compact.join("\n").presence)
      CatalogueEvent.record(kind: "wanted", work:, summary: "#{work.title}: wanting the #{label} edition in better condition")
      want
    end
  end

  # Is that printing already being hunted?
  def self.wanted?(work, edition)
    pub = edition.edition_identifiers.find { |i| i.id_type == "isfdb" }&.value&.to_i
    pub && Array(work.want&.printing_override_ids).include?(pub)
  end
end
