class BookmarksController < ApplicationController
  # Placing and removing a mark both re-render the same button frame, so the word
  # card updates in place and the reader can repaint the word underneath it.
  def create
    token = find_token(params[:token_id])
    @bookmark = current_user.bookmarks.find_or_create_by!(
      block_id: token.block_id,
      word_position: token.position
    )

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
                             .includes(block: :sentences)
  end

  private

  def render_button(token)
    render partial: "bookmarks/button",
           locals: { token: token,
                     bookmark: current_user.bookmarks.find_by(block_id: token.block_id,
                                                              word_position: token.position),
                     total: current_user.bookmarks.where(book_id: token.book_id).count }
  end
end
