class BooksController < ApplicationController
  before_action :set_book, only: %i[show read destroy]

  def index
    @books = current_user.books.recent
    @resume_points = ResumePoints.for(current_user, @books.select(&:ready?))
  end

  def new
    @book = current_user.books.new
  end

  def create
    @book = current_user.books.new(title: book_params[:title].presence)
    upload = book_params[:file]

    if upload.blank?
      @book.errors.add(:file, "is required")
      return render :new, status: :unprocessable_entity
    end

    @book.file.attach(upload)
    @book.source_filename = upload.original_filename
    @book.title ||= File.basename(upload.original_filename, ".*")
    @book.checksum = Digest::SHA256.file(upload.tempfile.path).hexdigest

    if @book.save
      BookIngestJob.perform_later(@book.id)
      redirect_to @book, notice: "Processing #{@book.title}. This takes about a minute for a full novel."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def show
    return unless @book.ready?

    resume = ResumePoints.for(current_user, [ @book ])[@book.id]
    redirect_to read_book_path(@book, **(resume&.path_options || {}))
  end

  def read
    return redirect_to @book unless @book.ready?

    @total_pages = @book.total_pages
    @page = params[:page].to_i.clamp(1, @total_pages)

    offset = (@page - 1) * Book::BLOCKS_PER_PAGE
    @blocks = @book.blocks
                   .where(position: offset...(offset + Book::BLOCKS_PER_PAGE))
                   .includes(book_image: { file_attachment: :blob })

    @tokens_by_block = tokens_for(@blocks)
    @statuses_by_lemma = statuses_by_lemma
    @bookmarked_token_ids = bookmarked_token_ids(offset)
    @bookmark_count = current_user.bookmarks.where(book: @book).count

    save_progress(offset)
  end

  def destroy
    @book.destroy
    redirect_to root_path, notice: "Removed #{@book.title}."
  end

  private

  def set_book
    @book = current_user.books.find(params[:id])
  end

  def book_params
    params.expect(book: [ :title, :file ])
  end

  # One query for the whole page, with the lemma text joined in so the renderer
  # never has to look a word up on its own.
  def tokens_for(blocks)
    Token.where(block_id: blocks.map(&:id))
         .left_joins(:lemma)
         .select("tokens.*", "lemmas.text AS lemma_text")
         .order(:block_id, :position)
         .group_by(&:block_id)
  end

  # Every saved word, mapped to how it should be highlighted. This is the whole
  # cost of the highlighting feature: one indexed lookup per page.
  def statuses_by_lemma
    current_user.vocab_entries.active.pluck(:lemma_id, :status).to_h
  end

  # Only the marks that fall on this page, matched on the same block range the page
  # was built from. This is what the denormalised block_position buys: an index hit
  # instead of an IN list of every token on screen.
  def bookmarked_token_ids(offset)
    current_user.bookmarks
                .where(book: @book, block_position: offset...(offset + Book::BLOCKS_PER_PAGE))
                .pluck(:token_id)
                .to_set
  end

  def save_progress(offset)
    progress = @book.progress_for(current_user)
    progress.block_position = offset
    progress.save! if progress.changed?
  end
end
