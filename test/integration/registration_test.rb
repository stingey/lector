require "test_helper"

class RegistrationTest < ActionDispatch::IntegrationTest
  test "the sign in page offers a way to create an account" do
    get new_session_path

    assert_response :success
    assert_select "a[href=?]", new_registration_path, text: "Create an account"
    assert_select "a[href=?]", new_password_path
  end

  test "creating an account signs the reader straight in" do
    assert_difference -> { User.count }, 1 do
      post registration_path, params: valid_params
    end

    assert_redirected_to root_path
    follow_redirect!
    assert_select ".topbar__brand", text: "Lector"
  end

  test "a new account starts with an empty library and word bank" do
    post registration_path, params: valid_params
    user = User.find_by(email_address: "nuevo@example.com")

    assert_equal 0, user.books.count
    assert_equal 0, user.vocab_entries.count
  end

  test "the email address is normalized before it is stored" do
    post registration_path, params: valid_params(email_address: "  Nuevo@Example.COM ")

    assert_equal "nuevo@example.com", User.last.email_address
  end

  test "a duplicate email is rejected regardless of case" do
    post registration_path, params: valid_params(email_address: users(:one).email_address.upcase)

    assert_response :unprocessable_entity
    assert_select ".flash--alert", text: /already been taken/
  end

  test "a mismatched confirmation is rejected" do
    assert_no_difference -> { User.count } do
      post registration_path, params: valid_params(password_confirmation: "different-one")
    end

    assert_response :unprocessable_entity
    assert_select ".flash--alert", text: /doesn't match/i
  end

  test "a short password is rejected" do
    assert_no_difference -> { User.count } do
      post registration_path, params: valid_params(password: "short", password_confirmation: "short")
    end

    assert_response :unprocessable_entity
    assert_select ".flash--alert", text: /too short \(minimum is 8 characters\)/
  end

  test "a malformed email is rejected" do
    assert_no_difference -> { User.count } do
      post registration_path, params: valid_params(email_address: "not-an-email")
    end

    assert_response :unprocessable_entity
    assert_select ".flash--alert", text: /does not look like an email address/
  end

  test "the form is redisplayed with the email kept but the password cleared" do
    post registration_path, params: valid_params(password_confirmation: "different-one")

    assert_select "input[name='user[email_address]'][value=?]", "nuevo@example.com"
    assert_select "input[name='user[password]'][value]", false, "the password should not be echoed back"
  end

  test "signing up requires no existing session" do
    get new_registration_path

    assert_response :success
  end

  private

  def valid_params(overrides = {})
    {
      user: {
        email_address: "nuevo@example.com",
        password: "una-contrasena-larga",
        password_confirmation: "una-contrasena-larga"
      }.merge(overrides)
    }
  end
end
