require "test_helper"

class VerifierTest < ActiveSupport::TestCase
  setup do
    Current.session = sessions(:david)
    @account, @board, @card = accounts("37s"), boards(:writebook), cards(:logo)
    clear_enqueued_jobs
  end

  test "an account and a board with nothing stored use zero bytes" do
    assert_usages @account => 0, @board => 0
  end

  test "a card image counts once the background work has run" do
    bytes = attach_image(@card, "moon.jpg")

    assert_equal 0, @account.reload.bytes_used
    assert_equal 0, @board.reload.bytes_used
    assert_usages @account => bytes, @board => bytes
  end

  test "images and embedded files add up per board and across the account" do
    image_bytes = attach_image(@card, "moon.jpg")
    card_blob = embed_in(@card, :description, "avatar.png")
    comment_blob = create_blob("moon.jpg")
    @card.comments.create!(body: rich_text_with(comment_blob), creator: users(:david))
    board_blob = embed_in(@board, :public_description, "avatar.png")
    other_bytes = attach_image(new_card(boards(:private), creator: users(:kevin)), "avatar.png")

    board_bytes = image_bytes + card_blob.byte_size + comment_blob.byte_size + board_blob.byte_size
    assert_usages @account => board_bytes + other_bytes, @board => board_bytes, boards(:private) => other_bytes
  end

  test "loose files, avatars and exports do not count" do
    ActiveStorage::Blob.create_and_upload!(io: StringIO.new("orphan" * 200), filename: "orphan.bin", content_type: "application/octet-stream")
    users(:david).avatar.attach(io: file_fixture("moon.jpg").open, filename: "avatar.jpg", content_type: "image/jpeg")
    exports(:pending_account_export).file.attach(io: StringIO.new("export" * 500), filename: "export.zip", content_type: "application/zip")

    assert_usages @account => 0, @board => 0
  end

  test "accounts do not see each other's bytes" do
    own_bytes = attach_image(@card, "moon.jpg")
    other_bytes = Current.set(account: accounts(:initech), session: sessions(:mike)) { attach_image(cards(:radio), "avatar.png") }

    assert_usages @account => own_bytes, @board => own_bytes, accounts(:initech) => other_bytes, boards(:miltons_wish_list) => other_bytes
  end

  test "reading the usage is a stored value, not a calculation" do
    assert_no_queries_match(/\b(active_storage_attachments|active_storage_blobs|action_text_rich_texts|cards|comments)\b/i) do
      assert_no_queries_match(/(SUM|COUNT)\(.*\bboards\b/i) do
        @account.bytes_used
        @board.bytes_used
      end
    end
  end

  test "replacing and removing a card image settles on the current image" do
    attach_image(@card, "moon.jpg")
    assert_usages @account => file_fixture("moon.jpg").size, @board => file_fixture("moon.jpg").size

    replacement_bytes = attach_image(@card, "avatar.png")
    assert_usages @account => replacement_bytes, @board => replacement_bytes

    @card.image.purge_later
    assert_usages @account => 0, @board => 0
  end

  test "editing, replacing and removing embedded files settles on the current embeds" do
    first = create_blob("moon.jpg")
    @card.update!(description: rich_text_with(first, text: "first"))
    assert_usages @account => first.byte_size, @board => first.byte_size

    @card.update!(description: rich_text_with(first, text: "same file, new text"))
    assert_usages @account => first.byte_size, @board => first.byte_size

    replacement = create_blob("avatar.png")
    @card.update!(description: rich_text_with(replacement, text: "replacement"))
    assert_usages @account => replacement.byte_size, @board => replacement.byte_size

    @card.update!(description: "<p>Nothing attached now</p>")
    assert_usages @account => 0, @board => 0
  end

  test "destroying a comment, a card and a board subtracts what each held" do
    board = @account.boards.create!(name: "Storage verifier board", creator: users(:david))
    card = new_card(board)
    image_bytes = attach_image(card, "moon.jpg")
    card_blob = embed_in(card, :description, "avatar.png")
    board_blob = embed_in(board, :public_description, "avatar.png")
    comment_blob = create_blob("moon.jpg")
    comment = card.comments.create!(body: rich_text_with(comment_blob), creator: users(:david))
    assert_usages @account => image_bytes + card_blob.byte_size + board_blob.byte_size + comment_blob.byte_size

    comment.destroy!
    assert_usages @account => image_bytes + card_blob.byte_size + board_blob.byte_size, board => image_bytes + card_blob.byte_size + board_blob.byte_size

    card.destroy!
    assert_usages @account => board_blob.byte_size, board => board_blob.byte_size

    board.destroy!
    assert_usages @account => 0
  end

  test "a job delivered twice does not count twice" do
    clear_performed_jobs
    blob = embed_in(@card, :description, "moon.jpg")
    perform_enqueued_jobs until enqueued_jobs.empty?
    performed_jobs.select { |job| job[:job] < ApplicationJob }.each { |job| ActiveJob::Base.execute(job) }

    assert_usages @account => blob.byte_size, @board => blob.byte_size
  end

  test "an ordinary attachment does not recount every blob in the account" do
    first_bytes = attach_image(@card, "moon.jpg")
    assert_usages @account => first_bytes, @board => first_bytes
    second_bytes = attach_image(new_card(boards(:private)), "avatar.png")

    assert_no_queries_match(/SUM\(.*byte_size.*active_storage_blobs/i) do
      perform_enqueued_jobs until enqueued_jobs.empty?
    end

    assert_usages @account => first_bytes + second_bytes, @board => first_bytes, boards(:private) => second_bytes
  end

  test "moving a card between boards moves its bytes, and deleting it takes them away" do
    card = new_card
    image_bytes = attach_image(card, "moon.jpg")
    card_blob = embed_in(card, :description, "avatar.png")
    comment_blob = create_blob("moon.jpg")
    card.comments.create!(body: rich_text_with(comment_blob), creator: users(:david))
    bytes = image_bytes + card_blob.byte_size + comment_blob.byte_size
    assert_usages @account => bytes, @board => bytes, boards(:private) => 0

    card.move_to(boards(:private))
    assert_usages @account => bytes, @board => 0, boards(:private) => bytes

    card.destroy!
    assert_usages @account => 0, @board => 0, boards(:private) => 0
  end

  test "a card created and destroyed before the background work runs settles at zero" do
    card = new_card
    attach_image(card, "moon.jpg")
    embed_in(card, :description, "avatar.png")
    card.destroy!

    assert_usages @account => 0, @board => 0
  end

  test "a rolled-back change leaves the usage alone" do
    blob = create_blob("moon.jpg")

    ActiveRecord::Base.transaction(requires_new: true) do
      @card.update!(description: rich_text_with(blob))
      raise ActiveRecord::Rollback
    end

    assert_usages @account => 0, @board => 0
  end

  test "a draft card counts, and an edit that touches no file changes nothing" do
    card = new_card(status: :drafted)
    bytes = attach_image(card, "moon.jpg")
    assert_usages @account => bytes, @board => bytes

    card.update!(title: "A title-only edit")
    assert_usages @account => bytes, @board => bytes
  end

  private
    def assert_usages(expected)
      perform_enqueued_jobs until enqueued_jobs.empty?
      expected.each { |owner, bytes| assert_equal bytes, owner.reload.bytes_used }
    end

    def attach_image(card, name)
      card.image.attach(io: file_fixture(name).open, filename: name, content_type: "image/#{name.end_with?(".png") ? "png" : "jpeg"}")
      card.image.blob.byte_size
    end

    def create_blob(name)
      ActiveStorage::Blob.create_and_upload!(io: file_fixture(name).open, filename: name, content_type: "image/#{name.end_with?(".png") ? "png" : "jpeg"}")
    end

    def embed_in(record, attribute, name)
      create_blob(name).tap { |blob| record.update!(attribute => rich_text_with(blob)) }
    end

    def rich_text_with(blob, text: "attached")
      "<p>#{text} #{ActionText::Attachment.from_attachable(blob).to_html}</p>"
    end

    def new_card(board = @board, creator: users(:david), status: :published)
      board.cards.create!(title: "Storage verifier #{SecureRandom.hex(4)}", creator: creator, status: status)
    end
end
