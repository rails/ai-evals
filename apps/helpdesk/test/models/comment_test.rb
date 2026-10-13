require "test_helper"

class CommentTest < ActiveSupport::TestCase
  test "comment text preserves intentional whitespace" do
    body = "  Please keep this indentation.\n\n"
    comments(:opening).update!(body: body)

    assert_equal body, comments(:opening).reload.body
  end

  test "comments require text and allow up to 10000 characters" do
    comment = comments(:opening)
    comment.body = " \n "
    assert_not comment.valid?
    assert comment.errors.of_kind?(:body, :blank)

    comment.body = "a" * 10_000
    assert comment.valid?

    comment.body += "a"
    assert_not comment.valid?
    assert comment.errors.of_kind?(:body, :too_long)
  end

  test "comments can be public or private but must declare their visibility" do
    comment = comments(:opening)
    comment.public = false
    assert comment.valid?

    comment.public = nil
    assert_not comment.valid?
    assert comment.errors.of_kind?(:public, :inclusion)
  end
end
