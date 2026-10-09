# frozen_string_literal: true

require 'net/http'
require 'openssl'
require 'uri'

module ObservabilityMcp
  class ApiError < Error
    attr_reader :status, :code

    def initialize(message, status: nil, code: nil)
      super(message)
      @status = status
      @code = code
    end

    def stream_not_found?
      code == 20_002 || (status == 404 && message.include?('stream not found'))
    end
  end

  # Thin HTTP client for the OpenObserve REST API (https://openobserve.ai/docs/reference/api/).
  # Every method returns parsed JSON or raises ApiError with a short, actionable message.
  class Client
    MAX_ERROR_CHARS = 400
    OPEN_TIMEOUT = 10

    def initialize(environment, timeout:)
      @environment = environment
      @base = URI(environment.url)
      @timeout = timeout
    end

    def organizations = get(%w[api organizations])

    def search(org, body, type:) = post(['api', org, '_search'], body, type: type)

    def streams(org, type: nil) = get(['api', org, 'streams'], type: type)

    def stream_schema(org, stream, type:) = get(['api', org, 'streams', stream, 'schema'], type: type)

    def latest_traces(org, stream, **params) = get(['api', org, stream, 'traces', 'latest'], **params)

    def prometheus(org, endpoint, **params) = get(['api', org, 'prometheus', 'api', 'v1', endpoint], **params)

    private

    def get(segments, **params) = request(Net::HTTP::Get, segments, params)

    def post(segments, body, **params) = request(Net::HTTP::Post, segments, params, body)

    def request(request_class, segments, params, body = nil)
      uri = build_uri(segments, params)
      request = request_class.new(uri)
      request.basic_auth(@environment.user, @environment.password)
      request['Accept'] = 'application/json'
      if body
        request['Content-Type'] = 'application/json'
        request.body = JSON.generate(body)
      end

      parse(perform(uri, request))
    rescue Net::OpenTimeout, Net::ReadTimeout
      raise ApiError, "OpenObserve (#{@environment.name}) did not answer within #{@timeout.to_i}s. " \
                      'Narrow the time window, add filters or lower the limit.'
    rescue SocketError, SystemCallError, OpenSSL::SSL::SSLError, IOError => e
      raise ApiError, "Cannot reach OpenObserve (#{@environment.name}, #{@base.host}): #{e.class}."
    end

    # Segments are percent-encoded, which keeps "/", "?" and "#" out of the path, but "." and ".." survive
    # encoding and would climb to other API paths — so org and stream names like that are rejected.
    def build_uri(segments, params)
      invalid = segments.find { %w[. ..].include?(it.to_s) || it.to_s.empty? }
      raise Error, "Invalid org or stream name #{invalid.to_s.inspect}." if invalid

      uri = @base.dup
      uri.path = "#{@base.path}/#{segments.map { URI.encode_uri_component(it.to_s) }.join('/')}"
      query = params.compact
      uri.query = URI.encode_www_form(query) unless query.empty?
      uri
    end

    def perform(uri, request)
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https',
                                          open_timeout: OPEN_TIMEOUT, read_timeout: @timeout) do |http|
        http.request(request)
      end
    end

    def parse(response)
      data = parse_json(response.body)
      if response.is_a?(Net::HTTPSuccess)
        return data unless data.nil?

        raise ApiError, "OpenObserve #{@environment.name} returned a non-JSON response (HTTP #{response.code}). " \
                        "Check that OO_#{@environment.name.upcase}_URL points at the OpenObserve API."
      end

      status = response.code.to_i
      code = data['code'] if data.is_a?(Hash)
      raise ApiError.new(error_message(status, code, data, response.body), status: status, code: code)
    end

    def parse_json(body)
      JSON.parse(body) unless body.to_s.strip.empty?
    rescue JSON::ParserError
      nil
    end

    # Some OpenObserve versions put the useful part in `error_detail` behind a generic `message`
    # ("Search SQL execute error"), so both are kept.
    def error_message(status, code, data, body)
      parts = data.is_a?(Hash) ? [data['message'] || data['error'], data['error_detail']] : [body]
      # OpenObserve lists every field of the stream on "field not found" — huge and useless here.
      detail = parts.map { it.to_s.strip.sub(/\s*Valid fields are .*/m, '') }.reject(&:empty?).uniq.join(': ')
      detail = 'empty or non-JSON response' if detail.empty?
      detail = "#{detail[0, MAX_ERROR_CHARS]}…" if detail.length > MAX_ERROR_CHARS

      ["OpenObserve #{@environment.name} returned HTTP #{status}: #{detail}", hint(status, code, detail)].compact.join(' ')
    end

    def hint(status, code, detail)
      return 'Call describe_stream to see valid field names.' if code == 20_004 || detail.include?('No field named')

      case [status, code]
      in [401, _] then "Check OO_#{@environment.name.upcase}_USER / OO_#{@environment.name.upcase}_PASSWORD."
      in [403, _] then 'The configured user lacks permission for this resource.'
      in [_, 20_002] then 'Call list_streams to see valid stream names.'
      in [404, _] then 'Check the org and stream names (list_environments / list_streams).'
      else nil
      end
    end
  end
end
