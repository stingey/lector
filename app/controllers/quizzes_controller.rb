class QuizzesController < ApplicationController
  # New words per session, so a big import does not turn into a wall of cards.
  NEW_PER_SESSION = 10

  before_action :set_filter

  def show
    @due_count = @filter.due_entries.count
    @new_count = @filter.unscheduled_entries.count
  end

  def card
    @entry = next_entry

    if @entry.nil?
      @remaining = 0
      return render :empty
    end

    @example = example_for(@entry)
    @previews = Srs.preview(@entry)
    @remaining = remaining_count
  end

  def answer
    entry = current_user.vocab_entries.find(params[:entry_id])
    rating = params[:rating]

    if Srs.rating_for(rating).blank?
      return redirect_to quiz_path, alert: "Unknown rating."
    end

    Srs.grade!(entry, rating: rating, sentence: sentence_from(params[:sentence_id]))

    redirect_to card_quiz_path(@filter.query_parameters)
  end

  private

  def set_filter
    @filter = VocabFilter.new(current_user, params)
  end

  # Due cards first, then a capped number of words never studied before.
  def next_entry
    @filter.due_entries.first || @filter.unscheduled_entries.limit(NEW_PER_SESSION).first
  end

  def remaining_count
    @filter.due_entries.count + [ @filter.unscheduled_entries.count, NEW_PER_SESSION ].min
  end

  # The sentence to quiz in. Prefers the passage where the word was first saved,
  # which is the context the reader actually has a memory of.
  def example_for(entry)
    token = entry.source_token || random_token(entry)
    return nil if token.blank?

    token = Token.left_joins(:lemma)
                 .select("tokens.*", "lemmas.text AS lemma_text")
                 .find(token.id)

    { token: token, sentence: token.sentence }
  end

  # No saved source: quote the sample occurrence the rollup recorded, from one of the
  # reader's books at random. Cheaper than sampling every occurrence, and the reader
  # cannot tell the difference.
  def random_token(entry)
    BookLemma.where(lemma_id: entry.lemma_id)
             .for_books(current_user.books.select(:id))
             .order(Arel.sql("RANDOM()"))
             .first
             &.sample_token
  end

  def sentence_from(id)
    return nil if id.blank?

    Sentence.joins(:book).where(books: { user_id: current_user.id }).find_by(id: id)
  end
end
