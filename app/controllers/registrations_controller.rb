class RegistrationsController < ApplicationController
  allow_unauthenticated_access
  rate_limit to: 10, within: 3.minutes, only: :create,
             with: -> { redirect_to new_registration_url, alert: "Try again later." }

  def new
    @user = User.new
  end

  def create
    @user = User.new(registration_params)

    if @user.save
      sample = install_sample_book(@user)
      start_new_session_for @user
      redirect_to after_authentication_url, notice: welcome_for(sample)
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  # A new reader lands on a library with a book in it. Never at the cost of the account:
  # if the bundled sample is missing or broken, they just get an empty library.
  def install_sample_book(user)
    DemoBook.install_for(user)
  rescue StandardError => error
    Rails.logger.error("[demo] could not install the sample book: #{error.class}: #{error.message}")
    nil
  end

  def welcome_for(sample)
    return "Welcome. Add a book to get started." if sample.nil?

    "Welcome. #{sample.title} is on your shelf to try, or add a book of your own."
  end

  def registration_params
    params.expect(user: [ :email_address, :password, :password_confirmation ])
  end
end
