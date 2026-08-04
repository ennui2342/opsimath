# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

# Genre — seeded from Thema's FL (Science fiction) and FM (Fantasy)
# subject trees per PHILOSOPHY.md principle 9, fetched directly from
# EDItEUR's own Thema code list (ns.editeur.org/thema/en/FL, /FM) rather
# than reconstructed from memory. FM (Fantasy) is a deliberate small
# extension beyond DATA_MODEL.md's literal "FL" wording — this is a
# personal SF *and* fantasy collection in practice (real Goodreads data:
# 15 books actually shelved "fantasy"), and Thema's FM tree is the same
# kind of controlled vocabulary FL is, not an invented one.
#
# bisac_code is only set on the two top-level rows (FIC028000, FIC009000
# — confirmed directly against BISG's own published list). The FL/FM
# sub-codes don't have a confidently-verified BISAC equivalent on hand;
# left blank rather than guessed, per DATA_MODEL.md's own allowance for
# a Genre row with no BISAC cross-reference.
THEMA_GENRES = [
  { thema_code: "FL", name: "Science fiction", bisac_code: "FIC028000" },
  { thema_code: "FLC", name: "Classic science fiction" },
  { thema_code: "FLG", name: "Science fiction: time travel / time slip" },
  { thema_code: "FLH", name: "Hard science fiction" },
  { thema_code: "FLJ", name: "Science fiction: cosy / cozy" },
  { thema_code: "FLM", name: "Science fiction: steampunk" },
  { thema_code: "FLP", name: "Science fiction: near future" },
  { thema_code: "FLQ", name: "Science fiction: apocalyptic and post-apocalyptic" },
  { thema_code: "FLR", name: "Science fiction: military" },
  { thema_code: "FLS", name: "Science fiction: space opera" },
  { thema_code: "FLU", name: "Science fiction: aliens / UFOs" },
  { thema_code: "FLW", name: "Science fiction: space exploration" },
  { thema_code: "FM", name: "Fantasy", bisac_code: "FIC009000" },
  { thema_code: "FMB", name: "Epic fantasy / high fantasy" },
  { thema_code: "FMH", name: "Historical fantasy" },
  { thema_code: "FMJ", name: "Fantasy: cosy / cozy" },
  { thema_code: "FMK", name: "Comic (humorous) fantasy" },
  { thema_code: "FMM", name: "Magical realism" },
  { thema_code: "FMR", name: "Fantasy romance / Romantic fantasy" },
  { thema_code: "FMS", name: "Superhero stories" },
  { thema_code: "FMT", name: "Dark fantasy" },
  { thema_code: "FMW", name: "Contemporary fantasy / Low fantasy" },
  { thema_code: "FMX", name: "Urban fantasy" }
].freeze

THEMA_GENRES.each do |attrs|
  Genre.find_or_create_by!(thema_code: attrs[:thema_code]) do |genre|
    genre.name = attrs[:name]
    genre.bisac_code = attrs[:bisac_code]
  end
end
