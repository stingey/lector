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

    @lemma_texts = lemma_texts_for(@blocks)
    @statuses_by_lemma = statuses_by_lemma
    @bookmarked_positions = bookmarked_positions(offset)
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

  # One query for every lemma on the page. The blob stores lemma ids rather than
  # repeating the text 3,000 times, so this is what turns them back into words.
  def lemma_texts_for(blocks)
    ids = blocks.flat_map(&:lemma_ids).uniq
    return {} if ids.empty?

    Lemma.where(id: ids).pluck(:id, :text).to_h
  end

  # Every saved word, mapped to how it should be highlighted. This is the whole
  # cost of the highlighting feature: one indexed lookup per page.
  def statuses_by_lemma
    current_user.vocab_entries.active.pluck(:lemma_id, :status).to_h
  end

  # Only the marks that fall on this page, matched on the same block range the page was
  # built from. This is what the denormalised block_position buys: an index hit instead
  # of a list of every word on screen.
  def bookmarked_positions(offset)
    current_user.bookmarks
                .where(book: @book, block_position: offset...(offset + Book::BLOCKS_PER_PAGE))
                .pluck(:block_id, :word_position)
                .group_by(&:first)
                .transform_values { |rows| rows.map(&:last).to_set }
  end

  def save_progress(offset)
    progress = @book.progress_for(current_user)
    progress.block_position = offset
    progress.save! if progress.changed?
  end
end
