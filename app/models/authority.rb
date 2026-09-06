# Authority control — one authorized ("preferred") form of a name plus a
# set of cross-references from its variants, per the library practice of
# the same name (https://en.wikipedia.org/wiki/Authority_control).
# opsimath already leans on bibliographic standards elsewhere (Thema for
# genre, ONIX for format); this is the mechanism that keeps a *controlled
# field* — a record column drawn from a vocabulary — pointing at real,
# agreed terms instead of whatever string a source happened to send.
#
# The model (AuthorityTerm / AuthorityVariant) and the settings UI are
# vocabulary-agnostic. What differs per vocabulary is the catalog-side
# behaviour — what "establish this term" actually does to existing
# records — and that lives behind a registered handler (see VOCABULARIES
# and Authority::Publishers). Adding a second vocabulary (contributor
# pen-names, series titles) is one handler class plus a registry entry;
# nothing here changes.
module Authority
  # vocabulary key => handler. A handler responds to:
  #   .label                    human name for the settings screen
  #   .controlled_fields        ["Edition#publisher", ...] — informational
  #   .apply(term)      -> Result   after a term/variant is established
  #   .retract(scope)   -> Result   after a term/variant is removed
  #   .usage(term)      -> { ... }  affected-record counts for the UI
  VOCABULARIES = {
    "publisher" => "Authority::Publishers"
  }.freeze

  def self.vocabularies = VOCABULARIES.keys

  def self.vocabulary?(name) = VOCABULARIES.key?(name.to_s)

  def self.handler(vocabulary)
    VOCABULARIES.fetch(vocabulary.to_s).constantize
  end

  # The lookup key for a name within a vocabulary — case, the "&"/"and"
  # connector, and every non-alphanumeric character folded away. Lifted
  # verbatim from Enrichment::IsfdbEditionEnricher#normalize_name (which
  # now delegates here) so the authority file and the enricher's own
  # string comparison agree on what "the same string" means. A vocabulary
  # that needs different folding can override via handler.normalize.
  def self.normalize(value)
    value.to_s.downcase.gsub(/\s*&\s*|\s+and\s+/, " ").gsub(/[^a-z0-9]/, "")
  end

  # The authorized form for `str` in `vocabulary`, or nil if the string
  # isn't in the file. One indexed lookup.
  def self.resolve(vocabulary, str)
    return nil if str.blank?

    AuthorityVariant.joins(:authority_term)
                    .find_by(vocabulary: vocabulary.to_s, normalized_label: normalize(str))
                    &.authority_term&.preferred_label
  end
end
