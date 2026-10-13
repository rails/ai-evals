module ApplicationHelper
  OPTION_LETTERS = ("A".."Z").to_a.freeze

  def logo(**options)
    tag.span(class: ["logo", options.delete(:class)], **options) do
      safe_join([tag.span("?", class: "logo__mark", "aria-hidden": true), "Quizzy"])
    end
  end

  def option_letter(index) = OPTION_LETTERS[index] || (index + 1).to_s

  # The number is nil when the current question was deactivated mid-game
  def question_progress(number, total)
    number ? t("question_progress.numbered", number:, total:) : t("question_progress.plain")
  end

  # "A. Title" for an answer option (options may have been edited after the game)
  def option_label(question, index)
    title = question.options.dig(index, "title") or return "—"
    "#{option_letter(index)}. #{title}"
  end

  def qr_code_svg(url)
    RQRCode::QRCode.new(url).as_svg(
      viewbox: true, use_path: true, module_size: 10, color: "0d0640", shape_rendering: "crispEdges"
    ).html_safe
  end

  def format_duration(ms)
    t("duration.seconds", value: number_with_precision(ms / 1000.0, precision: 1))
  end

  # Presence in a game (AnyCable presence over a signed stream): a player's page joins it, the big
  # screen watches it without counting itself. A presence ID is also the id of the element that a
  # "leave" removes, so it must not match anything on the page.
  def presence_source(run, id:, watcher: false)
    tag.send(:"turbo-cable-presence-source", "signed-stream-name": Turbo::StreamsChannel.signed_stream_name([run, :presence]),
      "presence-id": id, "ignore-self": watcher || nil, id: "presence_source", hidden: true,
      data: {turbo_permanent: true, controller: ("presence-count" if watcher)}) do
      # Sent to the others on join: a no-op stream action (the counters are all we need)
      safe_join([tag.template(tag.send(:"turbo-stream", tag.template, action: "append", target: "presence_noop")),
        tag.span(data: {presence_counter: true})])
    end
  end

  def flash_messages
    safe_join(flash.map { |type, message| tag.div(message, class: ["flash", ("flash--alert" if type.to_s == "alert")], role: "status") })
  end
end
