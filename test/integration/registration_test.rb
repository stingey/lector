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

  test "a new account starts with nothing of its own to read" do
    post registration_path, params: valid_params

    assert_equal 0, new_user.books.where(demo: false).count
    assert_equal 0, new_user.vocab_entries.count
  end

  test "a new account is handed the bundled sample so there is something to read" do
    with_bundled_sample do
      post registration_path, params: valid_params

      book = new_user.books.sole
      assert book.demo?
      assert book.ready?
      assert_equal 0, new_user.vocab_entries.count, "the sample comes with no words already saved"

      follow_redirect!
      assert_select ".flash", text: /Libro de muestra/
    end
  end

  # A book is a nicety; the account is the point.
  test "a sample that will not install still leaves the reader signed in" do
    corrupt = Tempfile.new([ "broken", ".json.gz" ])
    corrupt.write("not gzipped json at all")
    corrupt.close
    DemoBook.path = Pathname.new(corrupt.path)

    assert_difference -> { User.count }, 1 do
      post registration_path, params: valid_params
    end

    assert_redirected_to root_path
    follow_redirect!
    assert_select ".topbar__brand", text: "Lector"
    assert_equal 0, new_user.books.count
  ensure
    DemoBook.path = nil
    corrupt&.unlink
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

  test "an invite code is not asked for while signup is open" do
    get new_registration_path

    assert_select "input[name=invite_code]", false
    assert_difference -> { User.count }, 1 do
      post registration_path, params: valid_params
    end
  end

  test "a closed signup turns away anyone without the code" do
    with_invite_code "abrelasrejas" do
      get new_registration_path
      assert_select "input[name=invite_code]"

      assert_no_difference -> { User.count } do
        post registration_path, params: valid_params
      end
      assert_response :unprocessable_entity
      assert_select ".flash--alert", text: /invite code is not right/

      assert_no_difference -> { User.count } do
        post registration_path, params: valid_params.merge(invite_code: "wrong")
      end

      assert_difference -> { User.count }, 1 do
        post registration_path, params: valid_params.merge(invite_code: "abrelasrejas")
      end
      assert_redirected_to root_path
    end
  end

  private

  def with_invite_code(code)
    ENV["SIGNUP_INVITE_CODE"] = code
    yield
  ensure
    ENV.delete("SIGNUP_INVITE_CODE")
  end

  def new_user
    User.find_by(email_address: "nuevo@example.com")
  end

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
