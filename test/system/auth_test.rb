require "application_system_test_case"

class AuthTest < ApplicationSystemTestCase
  test "a new reader can sign up and lands in an empty library" do
    visit new_session_path
    take_screenshot_named "sign-in"

    click_on "Create an account"
    assert_selector ".auth__title", text: "Create an account"
    take_screenshot_named "sign-up"

    fill_in "user[email_address]", with: "nuevo@example.com"
    fill_in "user[password]", with: "una-contrasena-larga"
    fill_in "user[password_confirmation]", with: "una-contrasena-larga"
    click_on "Create account"

    assert_selector ".topbar__brand", text: "Lector"
    assert_selector ".empty", text: /No books yet/
  end

  test "a validation error is shown on the form rather than losing the entry" do
    visit new_registration_path

    fill_in "user[email_address]", with: "nuevo@example.com"
    fill_in "user[password]", with: "una-contrasena-larga"
    fill_in "user[password_confirmation]", with: "no-coincide"
    click_on "Create account"

    assert_selector ".flash--alert"
    assert_field "user[email_address]", with: "nuevo@example.com"
    take_screenshot_named "sign-up-error"
  end

  test "signing in with the wrong password says so" do
    visit new_session_path

    fill_in "email_address", with: users(:one).email_address
    fill_in "password", with: "wrong-password"
    click_on "Sign in"

    assert_selector ".flash--alert", text: /Try another email address or password/
    assert_field "email_address", with: users(:one).email_address
    take_screenshot_named "sign-in-error"
  end

  test "the password reset page matches the rest of the auth screens" do
    visit new_session_path
    click_on "Forgot your password?"

    assert_selector ".auth__title", text: "Reset your password"
    take_screenshot_named "password-reset"
  end

  private

  def take_screenshot_named(name)
    path = Rails.root.join("tmp/screenshots/#{name}.png")
    FileUtils.mkdir_p(path.dirname)
    page.save_screenshot(path.to_s)
  end
end
