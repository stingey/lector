# Everything needed for a sample book that ships inside the repo.
#
# static_path points at an image committed under app/assets/images, which is how the
# sample's illustrations survive a restart on a host with no object storage
# configured. Uploaded books keep using Active Storage and leave it null.
#
# demo marks the copy every new account is given, so installing it twice is a no-op
# and the library can tell it apart from a book the reader chose.
class AddBundledSampleSupport < ActiveRecord::Migration[8.0]
  def change
    add_column :book_images, :static_path, :string
    add_column :books, :demo, :boolean, null: false, default: false
  end
end
