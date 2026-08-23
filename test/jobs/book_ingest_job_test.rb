require "test_helper"

class BookIngestJobTest < ActiveJob::TestCase
  test "uploading a book enqueues ingest with the id, not the record" do
    user = users(:one)
    book = user.books.create!(title: "Sin procesar")

    assert_enqueued_with job: BookIngestJob, args: [ book.id ] do
      BookIngestJob.perform_later(book.id)
    end
  end

  test "a book deleted before the job runs is discarded rather than retried" do
    user = users(:one)
    book = user.books.create!(title: "Efímero")
    id = book.id
    book.destroy

    assert_nothing_raised { BookIngestJob.perform_now(id) }
  end
end
