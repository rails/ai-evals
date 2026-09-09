require "test_helper"

class VerifierTest < ActiveSupport::TestCase
  RECURRING_TASKS_IN_THE_BASE = %i[ deliver_bundled_notifications auto_postpone_all_due delete_unused_tags clear_solid_queue_finished_jobs
    cleanup_webhook_deliveries cleanup_magic_links cleanup_exports cleanup_imports yabeda_actioncable ]

  setup do
    Current.session = sessions(:david)
    clear_enqueued_jobs
  end

  test "an account cancelled more than thirty days ago goes, one inside the grace period stays" do
    due = cancelled_account(30.days.ago - 1.second)
    touched_lately = cancelled_account(31.days.ago).tap { |account| account.cancellation.update_columns(updated_at: Time.current) }
    recent = cancelled_account(30.days.ago + 1.second)
    reactivated = cancelled_account(40.days.ago).tap(&:reactivate)
    recent_tag = Tag.create!(account: recent, title: "Recent tag")

    run_the_schedule

    assert_not Account.exists?(due.id)
    assert_not Account.exists?(touched_lately.id)
    assert Account.exists?(recent.id)
    assert Tag.exists?(recent_tag.id)
    assert Account.exists?(reactivated.id)
    assert Account.exists?(accounts("37s").id)
  end

  test "everything the account owned goes with it, and nothing of anyone else's" do
    account, board, card, user, identity = accounts(:initech), boards(:miltons_wish_list), cards(:radio), users(:mike), identities(:mike)
    user_ids, board_ids = account.users.ids, account.boards.ids
    filter = nil
    Current.set(account: account, session: Session.new(identity: identity)) do
      user.create_settings!(bundle_email_frequency: :never)
      tag = Tag.create!(title: "Doomed tag")
      Column.create!(board: board, name: "Doomed", position: 0)
      export = Account::Export.create!(account: account, user: user)
      import = Account::Import.create!(account: account, identity: identity)
      Search::Query.create!(user: user, terms: "doomed search")
      Storage::Entry.create!(account: account, delta: 100, operation: "attach")
      Storage::Total.find_or_create_by!(owner: account).update!(bytes_stored: 100)
      Storage::Total.find_or_create_by!(owner: board).update!(bytes_stored: 50)
      account.create_cancellation!(initiated_by: user, created_at: 31.days.ago, updated_at: 31.days.ago)
      Board::Publication.create!(board: board)
      webhook = Webhook.create!(board: board, name: "Doomed", url: "https://example.com/webhook")
      event = Event.create!(board: board, creator: user, eventable: card, action: "card_published")
      Webhook::Delivery.create!(webhook: webhook, event: event)
      card.comments.create!(body: "Doomed comment")
      Step.create!(card: card, content: "Doomed step")
      Assignment.create!(card: card, assignee: user, assigner: user)
      Tagging.create!(card: card, tag: tag)
      Watch.create!(card: card, user: user)
      Pin.create!(card: card, user: user)
      Reaction.create!(reactable: card, content: "👍")
      Mention.create!(source: card, mentioner: user, mentionee: user)
      Closure.create!(card: cards(:paycheck), user: user)
      Card::Goldness.create!(card: card)
      Card::NotNow.create!(card: cards(:unfinished_thoughts), user: user)
      Card::ActivitySpike.create!(card: card)
      Notification.create!(user: user, source: event, creator: user)
      Notification::Bundle.create!(user: user, starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
      filter = user.filters.create!(sorted_by: "newest", tag_ids: [ tag.id ], board_ids: [ board.id ], assignee_ids: [ user.id ], creator_ids: [ user.id ], closer_ids: [ user.id ])
      card.image.attach(io: file_fixture("moon.jpg").open, filename: "doomed.jpg", content_type: "image/jpeg")
      ActiveStorage::VariantRecord.create!(blob: card.image.blob, variation_digest: "doomed-variant")
      export.file.attach(io: StringIO.new("doomed export"), filename: "doomed.zip", content_type: "application/zip")
      import.file.attach(io: StringIO.new("doomed import"), filename: "doomed-import.zip", content_type: "application/zip")
      perform_enqueued_jobs
    end
    search_record_ids = Search::Record.for(account.id).where(account_id: account.id).ids
    survivor = users(:david).filters.create!(sorted_by: "newest", tag_ids: [ Tag.create!(title: "Survivor tag").id ], board_ids: [ boards(:writebook).id ])
    Storage::Total.find_or_create_by!(owner: accounts("37s"))
    others_rows = rows_belonging_to(accounts("37s").id)

    run_the_schedule

    assert_not Account.exists?(account.id)
    assert_equal 0, rows_belonging_to(account.id)
    assert_empty User::Settings.where(user_id: user_ids)
    assert_empty Storage::Total.where(owner_type: "Account", owner_id: account.id).or(Storage::Total.where(owner_type: "Board", owner_id: board_ids))
    assert_empty Search::Record.for(account.id).where(account_id: account.id)
    search_record_ids.each { |id| assert_not Search::Record::SQLite::Fts.exists?(rowid: id) }
    assert_equal 0, filter_rows(filter.id)

    assert_equal others_rows, rows_belonging_to(accounts("37s").id)
    assert Storage::Total.exists?(owner_type: "Account", owner_id: accounts("37s").id)
    assert_operator filter_rows(survivor.id), :>, 0
  end

  test "running it again changes nothing" do
    due = cancelled_account(31.days.ago)

    run_the_schedule
    run_the_schedule

    assert_not Account.exists?(due.id)
  end

  test "stale search records go too, without touching another tenant on the same shard" do
    doomed, shard = accounts(:initech), Search::Record.for(accounts(:initech).id)
    survivor = accounts(:acme).users.create!(name: "Shared identity survivor", identity: identities(:mike), role: :member, verified_at: Time.current)
    stale = shard.create!(account_id: doomed.id, searchable_type: "Card", searchable_id: cards(:radio).id, card_id: cards(:radio).id, board_id: cards(:radio).board_id, title: "orphaned", content: "delete this", created_at: Time.current)
    cards(:radio).delete
    foreign = shard.create!(account_id: cards(:logo).account_id, searchable_type: "Card", searchable_id: cards(:logo).id, card_id: cards(:logo).id, board_id: cards(:logo).board_id, title: "foreign", content: "keep this", created_at: Time.current)
    doomed.create_cancellation!(initiated_by: users(:mike), created_at: 31.days.ago, updated_at: 31.days.ago)

    run_the_schedule

    assert_not Account.exists?(doomed.id)
    assert_not shard.exists?(id: stale.id)
    assert_not Search::Record::SQLite::Fts.exists?(rowid: stale.id)
    assert shard.exists?(id: foreign.id)
    assert Search::Record::SQLite::Fts.exists?(rowid: foreign.id)
    assert Identity.exists?(identities(:mike).id)
    assert User.exists?(survivor.id)
  end

  test "an incineration that cannot clear the search index leaves the account for the next run" do
    doomed, shard = accounts(:initech), Search::Record.for(accounts(:initech).id)
    held = shard.create!(account_id: doomed.id, searchable_type: "Card", searchable_id: cards(:radio).id, card_id: cards(:radio).id, board_id: cards(:radio).board_id, title: "held back", content: "refused once", created_at: Time.current)
    doomed.create_cancellation!(initiated_by: users(:mike), created_at: 31.days.ago, updated_at: 31.days.ago)

    ApplicationRecord.connection.execute "CREATE TRIGGER hold_search_records BEFORE DELETE ON search_records BEGIN SELECT RAISE(ABORT, 'search records are being held'); END"
    begin
      run_the_schedule
    rescue StandardError
      clear_enqueued_jobs
    end
    ApplicationRecord.connection.execute "DROP TRIGGER hold_search_records"
    assert Account.exists?(doomed.id)

    run_the_schedule

    assert_not Account.exists?(doomed.id)
    assert_not shard.exists?(id: held.id)
  end

  private
    def cancelled_account(cancelled_at)
      Account.create!(name: "Cancelled #{SecureRandom.hex(4)}").tap do |account|
        account.cancel(initiated_by: users(:david))
        account.cancellation.update_columns(created_at: cancelled_at, updated_at: cancelled_at)
      end
    end

    def run_the_schedule
      clear_enqueued_jobs
      Rails.application.config_for(:recurring, env: "production").except(*RECURRING_TASKS_IN_THE_BASE).each_value do |task|
        task[:class] ? task[:class].constantize.perform_later(*task[:args]) : SolidQueue::RecurringJob.perform_later(task[:command])
      end
      perform_enqueued_jobs until enqueued_jobs.empty?
    end

    def rows_belonging_to(account_id)
      connection = ApplicationRecord.connection
      connection.tables.select { |table| connection.column_exists?(table, :account_id) }.sum { |table| rows_in(table, account_id: account_id) }
    end

    def filter_rows(filter_id)
      %w[ filters_tags boards_filters assignees_filters creators_filters closers_filters ].sum { |table| rows_in(table, filter_id: filter_id) }
    end

    def rows_in(table, **conditions)
      Class.new(ApplicationRecord) { self.table_name = table }.where(**conditions).count
    end
end
