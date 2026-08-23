require "test_helper"

class SignInTest < ActionDispatch::IntegrationTest
  test "signing in reaches the library" do
    post session_path, params: { email_address: users(:one).email_address, password: "password" }

    assert_redirected_to root_path
    follow_redirect!
    assert_select ".topbar__brand", text: "Lector"
  end

  test "a wrong password keeps the email so only the password is retyped" do
    post session_path, params: { email_address: users(:one).email_address, password: "wrong" }

    follow_redirect!
    assert_select ".flash--alert", text: /Try another email address or password/
    assert_select "input[name=email_address][value=?]", users(:one).email_address
  end

  test "an unknown email is refused without revealing whether it exists" do
    post session_path, params: { email_address: "nobody@example.com", password: "password" }

    follow_redirect!
    assert_select ".flash--alert", text: /Try another email address or password/
  end

  test "signing out returns to the sign in page" do
    post session_path, params: { email_address: users(:one).email_address, password: "password" }
    delete session_path

    assert_redirected_to new_session_path
    get root_path
    assert_redirected_to new_session_path
  end

  test "an unauthenticated visitor is sent to sign in and back afterwards" do
    get words_path
    assert_redirected_to new_session_path

    post session_path, params: { email_address: users(:one).email_address, password: "password" }
    assert_redirected_to words_url
  end
end
