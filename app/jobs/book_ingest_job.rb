class BookIngestJob < ApplicationJob
  queue_as :default

  # Takes an id rather than the record: a book deleted between enqueue and pickup
  # should be dropped quietly, and GlobalID would raise a deserialization error
  # instead of the RecordNotFound this discards.
  discard_on ActiveRecord::RecordNotFound

  # A failed ingest is almost always a bad PDF rather than a transient fault, and
  # BookIngestor records the reason on the book for the reader to see.
  def perform(book_id)
    BookIngestor.new(Book.find(book_id)).call
  end
end
