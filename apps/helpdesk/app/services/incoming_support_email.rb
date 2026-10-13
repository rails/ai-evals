class IncomingSupportEmail
  class Discard < StandardError; end

  def initialize(mail)
    @mail = mail
  end

  def process
    data = parse
    return unless data
    account, ticket = destination(data.fetch(:recipient))
    return unless account
    if ticket
      process_reply(account, ticket, data)
    else
      process_new_ticket(account, data)
    end
  rescue ActiveRecord::RecordInvalid
    nil
  end

  private

  def process_new_ticket(account, data)
    sender = account.users.find_by(email: data.fetch(:sender))
    if sender
      receive_ticket(account, sender, data)
    else
      # Only customer creation needs coordination with invitation reservations.
      account.with_lock("FOR NO KEY UPDATE") do
        receive_ticket(account, account.users.find_by(email: data.fetch(:sender)), data)
      end
    end
  end

  def receive_ticket(account, sender, data)
    return if sender && (sender.suspended? || sender.staff?)
    return if Invitation.reserved?(account, data.fetch(:sender))
    receive_once(account, data.fetch(:message_id)) do
      unless sender
        sender = account.users.create!(name: data.fetch(:name), email: data.fetch(:sender),
          password: SecureRandom.hex(32), role: "customer", verified: false, suspended: false)
        EmailTokenLifecycle.issue!(sender, "verification")
      end
      ticket = TicketMutation.create!(account, sender,
        {"subject" => data.fetch(:subject), "comment" => {"body" => data.fetch(:body)}})
      ticket.update_columns(email_reply_token: SecureRandom.hex(24))
    end
  end

  def process_reply(account, ticket, data)
    sender = account.users.find_by(email: data.fetch(:sender))
    return unless sender
    return if sender.suspended? || sender.staff? || Invitation.reserved?(account, sender.email)
    return if sender.id != ticket.requester_id || ticket.account_id != account.id
    receive_once(account, data.fetch(:message_id)) do
      TicketMutation.update!(ticket, sender, {"comment" => {"body" => data.fetch(:body)}}, customer: true)
    end
  end

  def receive_once(account, message_id)
    # The unique receipt also handles simultaneous copies sent to different tickets.
    # Its insertion and the conversation changes commit or roll back together.
    InboundReceipt.transaction do
      receipt = InboundReceipt.create_or_find_by!(account: account, message_id_digest: EmailToken.digest(message_id))
      yield if receipt.previously_new_record?
    end
  end

  def parse
    # A present but blank Message-ID makes Mail invent an identifier when the
    # field is parsed. Require an identifier in the source before any decoding.
    identifiers = header_lines.filter_map do |line|
      name, value = line.split(":", 2)
      value if name.downcase == "message-id"
    end
    raise Discard unless identifiers.length == 1 && !identifiers.first.strip.empty?
    return if automatic?
    validate_header_text!
    message_id = @mail.message_id.to_s.strip
    raise Discard if message_id.empty?
    from_fields = fields("from")
    raise Discard unless from_fields.length == 1
    recipient_fields = fields("to") + fields("cc")
    raise Discard unless (from_fields + recipient_fields).all? { |field| field.errors.empty? }
    senders = from_fields.first.addresses || []
    raise Discard unless senders.length == 1
    sender = User.normalize_value_for(:email, senders.first)
    support_domain = Rails.application.config.x.support_domain
    raise Discard if sender.split("@").last == support_domain
    recipients = recipient_fields.flat_map(&:addresses).map { |address| address.strip.downcase }
    recipients = recipients.select { |address| address.split("@", -1).last == support_domain }.uniq
    raise Discard unless recipients.length == 1
    subject = utf8(@mail.subject.to_s).strip
    subject = "(no subject)" if subject.empty?
    part = plain_part(@mail)
    raise Discard unless part
    body = utf8(part.body.decoded.dup.force_encoding(part.charset || "UTF-8")).gsub("\r\n", "\n")
    raise Discard if body.strip.empty? || body.length > 10_000 || body.include?("\0")
    display_name = @mail[:from].display_names.first.to_s
    name = utf8(display_name).strip[0, 100]
    name = "Email customer" if name.empty?
    {message_id: message_id, sender: sender, recipient: recipients.first, subject: subject, body: body, name: name}
  rescue Discard, EncodingError, ArgumentError, Mail::UnknownEncodingType, Mail::Field::ParseError
    nil
  end

  def utf8(text)
    raise Discard unless text.valid_encoding?
    result = text.encode("UTF-8")
    raise Discard if result.include?("\0")
    result
  end

  def plain_part(part)
    return if part.attachment? || part.content_disposition.to_s.downcase.start_with?("attachment")
    if part.multipart?
      part.parts.each do |child|
        found = plain_part(child)
        return found if found
      end
      nil
    elsif part.mime_type.nil? || part.mime_type.downcase == "text/plain"
      part
    end
  end

  def automatic?
    fields("auto-submitted").any? { |field| field.value.to_s.strip.downcase != "no" } ||
      fields("precedence").any? { |field| %w[bulk list junk].include?(field.value.to_s.strip.downcase) }
  end

  def fields(name)
    # Mail collapses repeated singleton headers. Inspect their original fields
    # so duplicate From/To lines cannot disguise senders or support recipients.
    @original_fields ||= header_lines.map { |line| Mail::Field.parse(line) }
    @original_fields.select { |field| field.name.downcase == name }
  end

  def header_lines
    @header_lines ||= @mail.header.raw_source.split(/\r?\n(?![ \t])/).map { |line| line.gsub(/\r?\n[ \t]+/, " ") }
  end

  def validate_header_text!
    # Mail's decoded header helpers replace invalid encoded-word bytes. Validate
    # those bytes first instead of silently accepting a replacement character.
    (fields("subject") + fields("from")).each do |field|
      raw = field.value.to_s
      utf8(raw.dup.force_encoding("UTF-8"))
      raw.scan(/=\?([^?]+)\?([bq])\?([^?]*)\?=/i) do |charset, encoding, value|
        bytes = if encoding.downcase == "b"
          Base64.strict_decode64(value)
        else
          value.tr("_", " ").unpack1("M")
        end
        utf8(bytes.force_encoding(charset))
      end
    end
  end

  def destination(address)
    local = address.split("@", -1).first
    if (match = /\Areply\+([a-f0-9]{48})\z/.match(local))
      ticket = Ticket.find_by(email_reply_token: match[1])
      [ticket&.account, ticket]
    elsif local.match?(/\A[a-z0-9][a-z0-9-]{2,39}\z/)
      [Account.find_by(subdomain: local), nil]
    else
      [nil, nil]
    end
  end
end
