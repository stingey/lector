# Whether a stranger may create an account.
#
# Open by default, because that is what a personal app wants. Set SIGNUP_INVITE_CODE and
# the door closes: worth doing before a link goes anywhere public, since every reader who
# signs up gets a book installed for them and can spend the owner's translation credit.
class Registration
  class << self
    def invite_required?
      code.present?
    end

    def invite?(given)
      return true unless invite_required?
      return false if given.blank?

      ActiveSupport::SecurityUtils.secure_compare(given.to_s, code)
    end

    private

    def code
      ENV["SIGNUP_INVITE_CODE"].presence
    end
  end
end
