# A development login so you can get to the reader immediately after setup.
if Rails.env.development?
  user = User.find_or_create_by!(email_address: "reader@example.com") do |record|
    record.password = "password"
    record.password_confirmation = "password"
  end

  # The same bundled sample a new account is given. Already installed is fine.
  book = DemoBook.install_for(user)

  puts "Sign in as #{user.email_address} with password: password"
  puts book ? "Sample book ready: #{book.title} (#{book.total_pages} pages)" : "No bundled sample found"
end
