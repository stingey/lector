class WordsController < ApplicationController
  def index
    filter = VocabFilter.new(current_user, params)
    @filters = filter.filters
    @entries = filter.entries.to_a
    @scoped_params = filter.query_parameters
    @stats = stats
    @books = current_user.books.ready.order(:title)
    @occurrences = occurrence_counts(@entries)
    @forms = encountered_forms(@entries)
  end

  # Adding from the reader. Keyed on the token's lemma so every conjugation of the
  # word is covered by one click.
  def add
    @token = find_token(params[:token_id])

    if @token.lemma_id.blank?
      return render partial: "tokens/bank_button", locals: { token: @token, entry: nil }
    end

    @entry = current_user.vocab_entries.find_or_create_by!(lemma_id: @token.lemma_id) do |entry|
      entry.status = "learning"
      entry.source_book_id = @token.book_id
      entry.source_token_id = @token.id
      entry.gloss = suggested_gloss(@token)
    end

    render partial: "tokens/bank_button", locals: { token: @token, entry: @entry }
  end

  def show
    @entry = current_user.vocab_entries.for_listing.find(params[:id])
    @occurrences = @entry.occurrence_count
    @forms = @entry.encountered_forms
  end

  def update
    @entry = current_user.vocab_entries.find(params[:id])
    @entry.update!(update_params)
    redirect_to words_path, notice: "Saved #{@entry.lemma.text}."
  end

  def destroy
    @entry = current_user.vocab_entries.find(params[:id])
    @entry.destroy

    # Removing from inside the reader swaps the card's button back to "Add".
    if params[:token_id].present?
      @token = find_token(params[:token_id])
      return render partial: "tokens/bank_button", locals: { token: @token, entry: nil }
    end

    redirect_to words_path, notice: "Removed."
  end

  private

  def find_token(id)
    Token.joins(:book)
         .where(books: { user_id: current_user.id })
         .left_joins(:lemma)
         .select("tokens.*", "lemmas.text AS lemma_text")
         .find(id)
  end

  # One grouped read of the rollup for the whole page rather than a count per row.
  def occurrence_counts(entries)
    rollup_for(entries).group(:lemma_id).sum(:count)
  end

  # The distinct surface forms this reader has actually met, per lemma. A word can come
  # from more than one book, so the per-book maps are merged.
  def encountered_forms(entries)
    rollup_for(entries).pluck(:lemma_id, :surfaces)
                       .group_by(&:first)
                       .transform_values { |rows|
                         rows.map(&:last)
                             .each_with_object(Hash.new(0)) { |surfaces, totals|
                               surfaces.each { |surface, uses| totals[surface] += uses }
                             }
                             .sort_by { |_, uses| -uses }
                             .first(8)
                       }
  end

  def rollup_for(entries)
    lemma_ids = entries.map(&:lemma_id)
    return BookLemma.none if lemma_ids.empty?

    BookLemma.where(lemma_id: lemma_ids).for_books(current_user.books.select(:id))
  end

  def stats
    entries = current_user.vocab_entries
    {
      total: entries.count,
      learning: entries.learning.count,
      due: entries.due.count,
      this_week: entries.where(created_at: 1.week.ago..).count
    }
  end

  def suggested_gloss(token)
    Gloss.find_by(
      lemma_id: token.lemma_id,
      surface: token.surface,
      sentence_digest: token.sentence.digest
    )&.meaning
  end

  def update_params
    params.expect(vocab_entry: [ :gloss, :status, :note ])
  end
end
