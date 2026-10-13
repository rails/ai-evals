require "digest"

class CursorPage
  PAGINATION_KEYS = %w[size after before].freeze

  def self.invalid!
    raise ApiError.new(400, "Invalid cursor pagination")
  end

  def self.validate!(query)
    page = query["page"]
    return unless query.key?("page")
    return if page.is_a?(String)

    invalid! unless page.is_a?(Hash)
    invalid! if query.key?("per_page") || (page.keys - PAGINATION_KEYS).any?
    size = page["size"]
    invalid! unless size.is_a?(String) && size.match?(/\A[1-9]\d*\z/) && size.to_i <= 100
    invalid! if page.key?("after") && page.key?("before")
    %w[after before].each do |key|
      invalid! if page.key?(key) && (!page[key].is_a?(String) || page[key].empty?)
    end
  end

  def initialize(scope, request:, account:, actor:, clock: nil)
    @scope, @path, @clock = scope, request.path, clock
    query = request.query_parameters
    @page = query.fetch("page")
    @size = @page.fetch("size").to_i
    @backward = @page.key?("before")
    @filters = query.except("page", "per_page").sort.to_h
    @order = clock ? {clock => :desc, :id => :desc} : {id: :asc}
    # Bind the context without copying search text or credentials into a token.
    @context = Digest::SHA256.hexdigest(JSON.generate([1, account.id, actor.id, @path, @filters, @order]))
    # The database owns a per-business key, independent of process lifetime and
    # session rotation. Authenticated encryption hides even the boundary values.
    @cipher = ActiveSupport::MessageEncryptor.new(Digest::SHA256.digest(account.cursor_key),
      cipher: "aes-256-gcm", serializer: JSON, url_safe: true)
    @table = scope.klass.arel_table
  end

  def page
    cursor = @page[@backward ? "before" : "after"]
    rows = cursor ? boundary(decode(cursor), before: @backward) : @scope
    # Reverse the SQL order to obtain the *nearest* preceding rows, then restore
    # the public order. Read at most one extra row, never count the collection.
    order = if @backward
      @order.transform_values { |direction| (direction == :asc) ? :desc : :asc }
    else
      @order
    end
    records = rows.reorder(order).limit(@size + 1).to_a
    more = records.length > @size
    records = records.first(@size)
    records.reverse! if @backward
    return [[], {meta: {has_more: false, after_cursor: nil, before_cursor: nil}, links: {next: nil, prev: nil}}] if records.empty?

    first, last = position(records.first), position(records.last)
    before, after = encode(first), encode(last)
    earlier = @backward ? more : boundary(first, before: true).exists?
    later = @backward ? boundary(last, before: false).exists? : more
    [records, {
      meta: {has_more: more, after_cursor: after, before_cursor: before},
      links: {next: later ? link("after", after) : nil, prev: earlier ? link("before", before) : nil}
    }]
  end

  private

  def position(row)
    @clock ? [row.public_send(@clock).utc.iso8601(6), row.id] : [row.id]
  end

  def encode(position)
    @cipher.encrypt_and_sign(position, purpose: @context)
  end

  def decode(token)
    position = @cipher.decrypt_and_verify(token, purpose: @context)
    self.class.invalid! unless position.is_a?(Array) && position.length == (@clock ? 2 : 1) &&
      Uuid.valid?(position.last)
    if @clock
      self.class.invalid! unless position.first.is_a?(String)
      Time.iso8601(position.first)
    end
    position
  rescue ActiveSupport::MessageEncryptor::InvalidMessage, ArgumentError, TypeError
    self.class.invalid!
  end

  def boundary(position, before:)
    # Compare the saved values in the list's direction, not a lookup
    # of the anchor row, so deletion and changes to that row cannot shift pages.
    if @clock
      stamp, id = Time.iso8601(position.first), position.last
      connection = @scope.klass.connection
      table = connection.quote_table_name(@scope.klass.table_name)
      columns = [@clock, :id].map { |column| "#{table}.#{connection.quote_column_name(column)}" }.join(", ")
      # PostgreSQL can seek directly into the composite index with a row-value
      # comparison. An equivalent OR expression may scan the entire prefix.
      @scope.where("(#{columns}) #{before ? ">" : "<"} (?, ?)", stamp, id)
    else
      @scope.where(@table[:id].public_send(before ? :lt : :gt, position.last))
    end
  end

  def link(direction, cursor)
    query = @filters.merge("page" => {"size" => @size.to_s, direction => cursor})
    "#{@path}?#{query.to_query}"
  end
end
