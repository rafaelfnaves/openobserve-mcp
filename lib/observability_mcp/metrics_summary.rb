# frozen_string_literal: true

module ObservabilityMcp
  # Summarizes a Prometheus API `data` payload (matrix, vector or scalar) instead of returning every point:
  # labels shared by all series are printed once, and each series gets min/avg/max/last plus a sparkline.
  class MetricsSummary
    SPARK = %w[▁ ▂ ▃ ▄ ▅ ▆ ▇ █].freeze
    SPARK_WIDTH = 40
    LABEL_NOISE = /\A(?:aggregation_temporality|flag|is_monotonic|exemplars|start_time|count_bucket)\z/

    def initialize(data, limit:)
      @type = data['resultType']
      @result = data['result'] || []
      @limit = limit
    end

    def render
      return "scalar = #{@result[1]} @ #{time(@result[0])}" if %w[scalar string].include?(@type)
      return 'No series matched. Check the metric name (list_streams type=metrics) and label filters.' if @result.empty?

      series = @result.map { |entry| [labels(entry['metric'] || {}), points(entry)] }
      common = common_labels(series.map(&:first))
      lines = ["#{@type} · #{series.size} series#{common.empty? ? '' : " · common labels #{format_labels(common)}"}"]

      series.sort_by { |_, values| -(values.max || -Float::INFINITY) }.first(@limit).each do |labels, values|
        lines << "- #{format_labels(labels.reject { |key, _| common.key?(key) })} #{stats(values)}"
      end
      lines << "… #{series.size - @limit} more series (filter by label or aggregate, e.g. sum by (label) (...))" if series.size > @limit
      lines.join("\n")
    end

    private

    def labels(metric) = metric.reject { |key, _| key.match?(LABEL_NOISE) || key.match?(Formatter::NOISE) }

    def points(entry)
      raw = entry['values'] || [entry['value']].compact
      raw.filter_map do |_, value|
        number = Float(value, exception: false)
        number if number&.finite?
      end
    end

    def common_labels(all_labels)
      return all_labels.first || {} if all_labels.one?

      all_labels.reduce { |shared, labels| shared.select { |key, value| labels[key] == value } }
    end

    def stats(values)
      return '(no numeric points)' if values.empty?
      return "= #{num(values.last)}" if @type == 'vector'

      avg = values.sum / values.size
      "n=#{values.size} min=#{num(values.min)} avg=#{num(avg)} max=#{num(values.max)} last=#{num(values.last)} " \
        "#{sparkline(values)}"
    end

    def sparkline(values)
      buckets = values.each_slice((values.size.to_f / SPARK_WIDTH).ceil).map { it.sum / it.size }
      min, max = buckets.minmax
      return SPARK[0] * buckets.size if max == min

      buckets.map { SPARK[((it - min) / (max - min) * (SPARK.size - 1)).round] }.join
    end

    def format_labels(labels) = "{#{labels.map { |key, value| "#{key}=#{value}" }.join(' ')}}"

    # Compact numbers: 3, 7.778, 1.2e+20 (never hundreds of digits).
    def num(value)
      return format('%.4g', value) if value.abs >= 1e15 || (value.nonzero? && value.abs < 1e-3)

      value.round(3).then { it == it.to_i ? it.to_i.to_s : it.to_s }
    end

    def time(seconds) = Time.at(seconds.to_f).utc.iso8601
  end
end
