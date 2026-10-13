require "test_helper"

class AccountTest < ActiveSupport::TestCase
  test "names and subdomains are normalized before saving" do
    account = Account.create!(name: " New Company ", subdomain: " NEW-COMPANY ")

    assert_equal "New Company", account.reload.name
    assert_equal "new-company", account.subdomain
    assert_equal account, Account.find_by(subdomain: " NEW-COMPANY ")
  end

  test "invalid names and subdomains cannot be saved" do
    account = accounts(:acme)
    original = account.attributes

    [
      {name: " "}, {name: "a" * 101}, {subdomain: nil}, {subdomain: "ab"},
      {subdomain: "a" * 41}, {subdomain: "-acme"}, {subdomain: "acme.test"},
      {subdomain: "acme\nother"}
    ].each do |attributes|
      assert_not account.update(attributes), "Accepted #{attributes.inspect}"
      assert account.errors[attributes.keys.sole].any?
      assert_equal original, account.reload.attributes
    end
  end

  test "normalization prevents duplicate subdomains" do
    account = Account.new(name: "Duplicate", subdomain: " #{accounts(:acme).subdomain.upcase} ")

    assert_no_difference "Account.count" do
      assert_not account.save
    end
    assert_includes account.errors[:subdomain], "has already been taken"
  end
end
