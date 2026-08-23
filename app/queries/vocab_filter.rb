# Shared filtering for the word bank and the quiz.
#
# Living in one place is what lets "Quiz these" respect whatever filter the reader
# currently has applied, so you can drill a single book or a single part of speech.
class VocabFilter
  SORTS = {
    "added" => { created_at: :desc },
    "due" => { due_at: :asc },
    "recent_review" => { last_reviewed_at: :desc }
  }.freeze

  DEFAULT_SORT = "added"

  attr_reader :filters

  def initialize(user, params)
    @user = user
    @filters = {
      status: params[:status].presence,
      pos: params[:pos].presence,
      book_id: params[:book_id].presence,
      query: params[:query].presence,
      sort: sort_from(params[:sort])
    }
  end

  def entries
    sorted(apply(user.vocab_entries.for_listing))
  end

  def due_entries(at: Time.current)
    apply(user.vocab_entries.for_listing).active.where(due_at: ..at).order(:due_at)
  end

  # Words saved but never scheduled yet, which become the new cards in a session.
  def unscheduled_entries
    apply(user.vocab_entries.for_listing).active.where(due_at: nil).order(:created_at)
  end

  def scoped?
    filters.slice(:status, :pos, :book_id, :query).values.any?(&:present?)
  end

  def query_parameters
    filters.compact.transform_keys(&:to_s)
  end

  private

  attr_reader :user

  def sort_from(value)
    return value if SORTS.key?(value) || value == "alphabetical"

    DEFAULT_SORT
  end

  def apply(scope)
    scope = scope.where(status: filters[:status]) if filters[:status]
    scope = scope.where(source_book_id: filters[:book_id]) if filters[:book_id]
    scope = scope.joins(:lemma).where(lemmas: { pos: filters[:pos] }) if filters[:pos]

    if filters[:query]
      term = "%#{ActiveRecord::Base.sanitize_sql_like(filters[:query])}%"
      scope = scope.joins(:lemma).where("lemmas.text ILIKE :t OR vocab_entries.gloss ILIKE :t", t: term)
    end

    scope
  end

  def sorted(scope)
    return scope.joins(:lemma).order("lemmas.text ASC") if filters[:sort] == "alphabetical"

    scope.order(SORTS.fetch(filters[:sort], SORTS.fetch(DEFAULT_SORT)))
  end
end
