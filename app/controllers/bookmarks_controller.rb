class BookmarksController < ApplicationController
  # Placing and removing a mark both re-render the same button frame, so the word
  # card updates in place and the reader can repaint the word underneath it.
  def create
    token = find_token(params[:token_id])
    @bookmark = current_user.bookmarks.find_or_create_by!(token: token)

    render_button(token)
  end

  # Removal happens from two places: the word card, which wants the button back, and
  # the bookmarks list, which wants the list back without that row.
  def destroy
    bookmark = current_user.bookmarks.find(params[:id])
    token = bookmark.token
    book = bookmark.book
    bookmark.destroy

    if turbo_frame_request?
      render_button(token)
    else
      redirect_to book_bookmarks_path(book), notice: "Bookmark removed."
    end
  end

  def index
    @book = current_user.books.find(params[:book_id])
    @bookmarks = current_user.bookmarks
                             .where(book: @book)
                             .in_reading_order
                             .includes(token: %i[sentence block])
  end

  private

  def find_token(id)
    Token.joins(:book).where(books: { user_id: current_user.id }).find(id)
  end

  def render_button(token)
    render partial: "bookmarks/button",
           locals: { token: token,
                     bookmark: current_user.bookmarks.find_by(token: token),
                     total: current_user.bookmarks.where(book_id: token.book_id).count }
  end
end
