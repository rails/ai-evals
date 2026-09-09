require "application_system_test_case"

class VerifierTest < ApplicationSystemTestCase
  setup do
    @board, @author = boards(:writebook), users(:david)
    @column = with_current_user(@author) { @board.columns.create!(name: "Fresh lane") }
    sign_in_as @author
  end

  test "dragging a card into a column moves it there" do
    card = cards(:buy_domain)

    on_the_board { drag card, onto: dom_id(@column) }

    assert_selector "body[data-saved]"
    assert_equal @column, card.reload.column
  end

  test "dragging a card onto Done finishes it" do
    card = in_the_column(cards(:text))

    on_the_board { drag card, onto: "closed-cards" }

    assert_selector "body[data-saved]"
    assert_predicate card.reload, :closed?
  end

  test "dragging a card onto Not Now shelves it" do
    card = in_the_column(cards(:layout))

    on_the_board { drag card, onto: "not-now" }

    assert_selector "body[data-saved]"
    assert_predicate card.reload, :postponed?
  end

  test "the board is already settled while the save is still in flight" do
    golden, card = in_the_column(cards(:shipping)), cards(:buy_domain)
    with_current_user(@author) { golden.gild }

    on_the_board hold_the_network: true do
      drag card, onto: dom_id(@column)
      assert_selector "body[data-saving='1']"

      assert_equal [ article(golden), article(card) ], cards_in_the_column
      assert_equal "2", find("##{dom_id(@column)} .cards__expander-count").text
    end
  end

  test "nothing shifts once the save lands" do
    golden, card = in_the_column(cards(:shipping)), cards(:buy_domain)
    with_current_user(@author) { golden.gild }

    on_the_board do
      drag card, onto: dom_id(@column)
      assert_selector "##{dom_id(@column)} ##{article(card)}", visible: :all
      settled = cards_in_the_column

      assert_selector "body[data-saved][data-saving='0']"
      page.has_selector?("body[data-rendered]", wait: 2)
      assert_equal @column, card.reload.column
      assert_equal settled, cards_in_the_column

      visit board_url(@board)
      assert_equal settled, cards_in_the_column
    end
  end

  private
    def article(card) = dom_id(card, :article)

    def in_the_column(card)
      with_current_user(@author) { card.triage_into(@column) }
      card
    end

    def cards_in_the_column
      find("##{dom_id(@column)}").all("article[id]", visible: :all).map { |node| node[:id] }
    end

    def on_the_board(hold_the_network: false)
      visit board_url(@board)
      assert_selector "article[id^='article_card_']", visible: :all
      page.execute_script <<~JS, hold_the_network
        const hold = arguments[0], native = window.fetch
        let saving = 0
        window.fetch = (...args) => {
          document.body.dataset.saving = ++saving
          return (hold ? new Promise(() => {}) : native(...args)).finally(() => { document.body.dataset.saving = --saving; document.body.dataset.saved = true })
        }
        for (const event of [ "turbo:before-stream-render", "turbo:frame-render" ]) addEventListener(event, () => document.body.dataset.rendered = true)
        document.body.dataset.saving = 0
      JS
      yield
    end

    def drag(card, onto:)
      assert_selector "##{article(card)}", visible: :all
      assert_selector "##{onto}", visible: :all

      page.execute_script <<~JS, article(card), onto
        const article = document.getElementById(arguments[0])
        const item = article.closest("[draggable=true]") || article.querySelector("[draggable=true]") || article
        let target = document.getElementById(arguments[1])
        while (target.lastElementChild) target = target.lastElementChild
        const dt = new DataTransfer()
        const fire = (node, type) => node.dispatchEvent(new DragEvent(type, { bubbles: true, cancelable: true, dataTransfer: dt }))
        fire(item, "dragstart")
        requestAnimationFrame(() => requestAnimationFrame(() => {
          fire(target, "dragenter")
          if (!fire(target, "dragover")) fire(target, "drop")
          fire(item, "dragend")
        }))
      JS
    end
end
