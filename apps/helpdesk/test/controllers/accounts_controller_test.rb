require "test_helper"

class AccountsControllerTest < ActionDispatch::IntegrationTest
  test "signup creates an account and unverified administrator and sends a verification link" do
    assert_emails 1 do
      assert_difference ["Account.count", "User.count", "EmailToken.count"], +1 do
        post account_create_path, params: {account: {
          name: " New Company ", subdomain: " NEW-COMPANY ",
          admin: {name: " New Owner ", email: " OWNER@NEW.EXAMPLE ", password: "secret123456"}
        }}, as: :json
      end
    end

    assert_response :created
    account = Account.find(response.parsed_body.dig("account", "id"))
    owner = account.users.sole
    assert_equal "new-company", account.subdomain
    assert_equal "New Company", account.name
    assert_equal "New Owner", owner.name
    assert_equal "owner@new.example", owner.email
    assert_equal "admin", owner.role
    assert_not owner.verified?
    assert owner.authenticate("secret123456")
    assert_equal [owner.email], ActionMailer::Base.deliveries.sole.to
    assert_equal owner.email_tokens.sole.token_digest, EmailToken.digest(email_token_from)
    assert_not response.parsed_body.fetch("user").key?("password_digest")
  end

  test "invalid signup leaves no account user or email behind" do
    assert_no_emails do
      assert_no_difference ["Account.count", "User.count", "EmailToken.count"] do
        post account_create_path, params: {account: {
          name: "New Company", subdomain: "new-company",
          admin: {name: "Owner", email: "owner@new.example", password: "short"}
        }}, as: :json
      end
    end

    assert_response :unprocessable_entity
  end

  test "signup cannot replace an existing account" do
    assert_no_emails do
      assert_no_difference ["Account.count", "User.count", "EmailToken.count"] do
        post account_create_path, params: {account: {
          name: "Replacement", subdomain: accounts(:acme).subdomain,
          admin: {name: "Owner", email: "owner@new.example", password: "secret123456"}
        }}, as: :json
      end
    end

    assert_response :unprocessable_entity
  end

  test "public portal returns only tenant branding" do
    get portal_path, headers: account_headers(:acme)

    assert_response :ok
    assert_equal({"portal" => {"name" => accounts(:acme).name, "subdomain" => accounts(:acme).subdomain}}, response.parsed_body)
  end

  test "account details require a session belonging to that account" do
    sign_in :owner

    get account_path, headers: @headers
    assert_response :ok
    assert_equal accounts(:acme).id, response.parsed_body.dig("account", "id")

    get account_path, headers: @headers.merge(account_headers(:globex))
    assert_response :unauthorized

    get account_path, headers: account_headers(:acme)
    assert_response :unauthorized
  end
end
