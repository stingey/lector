# A development login so you can get to the reader immediately after setup.
if Rails.env.development?
  user = User.find_or_create_by!(email_address: "reader@example.com") do |record|
    record.password = "password"
    record.password_confirmation = "password"
  end

  puts "Sign in as #{user.email_address} with password: password"
end
