namespace :import do
  desc "Import a langflash CSV export into a user's word bank: rake import:langflash EMAIL=you@example.com FILE=cards.csv"
  task langflash: :environment do
    email = ENV.fetch("EMAIL")
    file = ENV.fetch("FILE")

    user = User.find_by!(email_address: email)
    result = LangflashImporter.new(user).import_csv(file)

    puts "Imported #{result.imported}, skipped #{result.skipped} already present."

    if result.unmatched.any?
      puts "Could not place #{result.unmatched.size}: #{result.unmatched.first(20).join(', ')}"
    end
  end
end
