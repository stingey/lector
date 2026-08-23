class User < ApplicationRecord
  # Deliberately permissive: enough to catch a typo, not enough to reject a valid
  # address. Delivery is the real test of an email.
  EMAIL_FORMAT = /\A[^@\s]+@[^@\s]+\.[^@\s]+\z/

  # bcrypt silently truncates beyond 72 bytes, so the form caps input there too.
  MAX_PASSWORD_LENGTH = 72

  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :books, dependent: :destroy
  has_many :vocab_entries, dependent: :destroy
  has_many :reading_progresses, dependent: :destroy
  has_many :bookmarks, dependent: :delete_all
  has_many :saved_lemmas, through: :vocab_entries, source: :lemma

  # Runs before validation, so uniqueness compares normalized addresses.
  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :email_address, presence: true,
                            format: { with: EMAIL_FORMAT, message: "does not look like an email address" },
                            uniqueness: { case_sensitive: false }

  validates :password, length: { minimum: 8, maximum: MAX_PASSWORD_LENGTH }, allow_nil: true
end
