require "application_system_test_case"

class VerifierTest < ApplicationSystemTestCase
  setup do
    ActionMailer::Base.deliveries.clear
    @david, @jason, @kevin, @account = identities(:david), identities(:jason), identities(:kevin), accounts("37s")
  end

  test "typing your email gets a code by email, and the code signs you in on this device" do
    type_email @david.email_address
    type_code code_sent_to(@david.email_address)

    assert_equal @david.id, signed_in_on(:device)
  end

  test "a code that has been used is used up" do
    type_email @david.email_address
    code = code_sent_to(@david.email_address)
    type_code code
    assert_equal @david.id, signed_in_on(:device)

    using_session(:device) { Capybara.reset_session! }
    type_email @david.email_address
    type_code code

    assert_not_equal @david.id, signed_in_on(:device)
  end

  test "a code stops working after fifteen minutes" do
    type_email @david.email_address
    code = code_sent_to(@david.email_address)

    travel 16.minutes do
      type_email @david.email_address
      type_code code
      assert_not_equal @david.id, signed_in_on(:device)
    end
  end

  test "an address with no account gets exactly the answer an address with one gets" do
    with_multi_tenant_mode(false) do
      assert_not Account.accepting_signups?

      assert_equal answer_to(@david.email_address), answer_to("nobody-#{SecureRandom.hex(4)}@example.com")
    end
  end

  test "a code is only good on the device that asked for it" do
    type_email @kevin.email_address, on: :kevins
    type_email @jason.email_address, on: :jasons
    code = code_sent_to(@jason.email_address)

    type_code code, on: :kevins
    assert_not_equal @jason.id, signed_in_on(:kevins)
    assert_not_equal @kevin.id, signed_in_on(:kevins)

    jasons_page = using_session(:jasons) { current_url }
    using_session(:bystander) do
      visit jasons_page
      type_code code, on: :bystander if has_css?("input[name=code]", wait: 0)
    end
    assert_not_equal @jason.id, signed_in_on(:bystander)
  end

  test "a new person signs up with a code and is brought to finishing their sign-up" do
    assert Account.accepting_signups?
    email = "newbie-#{SecureRandom.hex(4)}@example.com"

    type_email email, from: new_signup_path(script_name: nil)
    type_code code_sent_to(email)

    using_session(:device) { assert_selector "form input[name*=name]" }
    assert_equal Identity.find_by!(email_address: email).id, signed_in_on(:device)
  end

  test "joining with a join code gets you a sign-in code and brings you into the account" do
    email = "joiner-#{SecureRandom.hex(4)}@example.com"

    type_email email, from: join_path(code: @account.join_code.code, script_name: @account.slug)
    type_code code_sent_to(email)

    using_session(:device) { assert current_path.start_with?(@account.slug) }
    identity = Identity.find_by!(email_address: email)
    assert_equal identity.id, signed_in_on(:device)
    assert @account.users.find_by(identity: identity)
  end

  private
    def type_email(email, from: new_session_path(script_name: nil), on: :device)
      using_session(on) do
        visit from
        submit "input[type=email]", email
      end
      perform_enqueued_jobs
    end

    def type_code(code, on: :device)
      using_session(on) { submit "input[name=code]", code }
    end

    def submit(field, value)
      execute_script "document.body.dataset.submitting = true"
      find(field).fill_in(with: value).send_keys(:enter)
      assert_no_selector "body[data-submitting]"
    end

    def signed_in_on(device)
      using_session(device) do
        visit my_identity_path(script_name: nil, format: :json)
        JSON.parse(text)["id"] if text.start_with?("{")
      end
    end

    def answer_to(email)
      type_email email, on: email
      using_session(email) { [ current_path, text.squish.gsub(email, "EMAIL") ] }
    end

    def code_sent_to(email)
      subject = ActionMailer::Base.deliveries.reverse.find { |mail| mail.to.include?(email) }.subject
      subject.scan(/\b[A-Za-z0-9]{6}\b/).find { |token| !token.match?(/\A[A-Z]?[a-z]+\z/) }
    end
end
