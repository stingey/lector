class ApplicationController < ActionController::Base
  include Authentication

  allow_browser versions: :modern

  helper_method :current_user

  private

  def current_user
    Current.user
  end

  # Words are addressed as "<block_id>-<position>", and only inside books the signed in
  # reader owns.
  def find_token(id)
    Token.locate(Block.where(book_id: current_user.books.select(:id)), id)
  end
end
