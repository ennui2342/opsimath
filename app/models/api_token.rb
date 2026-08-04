# Automation/integration access, separate from the human User/Session
# login — see docs/PHILOSOPHY.md principle 19 and docs/DATA_MODEL.md's
# User/Session/ApiToken entry. No scopes/permissions system: single-user,
# single-purpose tokens are enough until a real need for more shows up.
class ApiToken < ApplicationRecord
  belongs_to :user

  validates :name, presence: true

  # Only ever returned once, at issuance — never stored or retrievable
  # again afterward, only its digest is.
  def self.issue!(user:, name:)
    raw_token = SecureRandom.hex(32)
    token = create!(user: user, name: name, token_digest: digest(raw_token))
    [ token, raw_token ]
  end

  def self.authenticate(raw_token)
    return nil if raw_token.blank?
    token = find_by(token_digest: digest(raw_token))
    token&.touch(:last_used_at)
    token
  end

  def self.digest(raw_token)
    Digest::SHA256.hexdigest(raw_token)
  end
end
