# frozen_string_literal: true

module ObservabilityMcp
  # Builds the request body for POST /api/{org}/_search, taking care of the details that used to
  # break hand-written queries: quoted stream names, the microsecond window, a bounded size,
  # and read-only single statements.
  class SearchQuery
    STATEMENT = /\A(?:SELECT|WITH)\b/i
    # String literals and quoted identifiers stay opaque; comments are dropped.
    SEGMENT = %r{('(?:[^']|'')*'|"(?:[^"]|"")*"|--[^\n]*|/\*.*?\*/)}m
    COMMENT = %r{\A(?:--|/\*)}
    BARE_TABLE = /\b(FROM|JOIN)(\s+)([A-Za-z_][\w\-]*+)/i
    NEEDS_QUOTES = /[^A-Za-z0-9_]/
    TRAILING_LIMIT = /\bLIMIT\s+(\d+)(\s+OFFSET\s+\d+)?\s*\z/i

    attr_reader :sql, :time_range, :size

    def self.ident(name) = %("#{name.to_s.gsub('"', '""')}")

    def self.literal(value) = "'#{value.to_s.gsub("'", "''")}'"

    # SELECT <columns> FROM "<stream>" [WHERE (c1) AND (c2)] [ORDER BY ...] LIMIT n
    def self.select(stream:, limit:, columns: nil, where: [], order_by: '_timestamp DESC', group_by: nil)
      conditions = Array(where).map { it.to_s.strip }.reject(&:empty?)
      sql = +"SELECT #{Array(columns).empty? ? '*' : Array(columns).join(', ')} FROM #{ident(stream)}"
      sql << " WHERE #{conditions.map { "(#{it})" }.join(' AND ')}" if conditions.any?
      sql << " GROUP BY #{group_by}" if group_by
      sql << " ORDER BY #{order_by}" if order_by
      sql << " LIMIT #{Integer(limit)}"
    end

    # Validates and normalizes agent-written SQL: a single SELECT/WITH statement without comments,
    # stream names that need it quoted (`FROM my-stream` → `FROM "my-stream"`), and a LIMIT no larger
    # than `limit` (appended when missing, lowered when bigger).
    def self.normalize(sql, limit:)
      segments = sql.to_s.split(SEGMENT).each_with_index.filter_map do |segment, index|
        next segment if index.even?

        segment.match?(COMMENT) ? ' ' : segment
      end
      code = segments.each_slice(2).map(&:first).join(' ').strip

      unless code.match?(STATEMENT) && !code.chomp(';').include?(';')
        raise Error, 'Only a single SELECT or WITH statement is allowed.'
      end
      raise Error, 'SQL must read FROM a stream, e.g. SELECT * FROM "default".' unless code.match?(/\bFROM\b/i)

      sql = segments.each_with_index.map { |segment, index| index.odd? ? segment : quote_bare_tables(segment) }
                    .join.strip.sub(/\s*;\z/, '')
      cap_limit(sql, Integer(limit))
    end

    def self.quote_bare_tables(code)
      code.gsub(BARE_TABLE) do
        keyword, space, name = ::Regexp.last_match.captures
        "#{keyword}#{space}#{name.match?(NEEDS_QUOTES) ? ident(name) : name}"
      end
    end

    def self.cap_limit(sql, limit)
      match = TRAILING_LIMIT.match(sql)
      return "#{sql} LIMIT #{limit}" unless match
      return sql if match[1].to_i <= limit

      "#{match.pre_match}LIMIT #{limit}#{match[2]}"
    end
    private_class_method :quote_bare_tables, :cap_limit

    def initialize(sql, time_range:, size:)
      @sql = sql
      @time_range = time_range
      @size = size
    end

    def to_h
      { query: { sql: sql, start_time: time_range.start_us, end_time: time_range.end_us, from: 0, size: size } }
    end
  end
end
