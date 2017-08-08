require "./http_redirects/*"

require "http"

module HTTP
  class Client
    private def exec_internal_single(request)
      decompress = set_defaults request
      request.to_io(socket)
      socket.flush
      response = HTTP::Client::Response.from_io?(socket, ignore_body: request.ignore_body?, decompress: decompress)
      response.not_nil!.request = request
      response
    end

    class Response
      property :request
      @request : HTTP::Request?

      # Returns `true` if the response status code is between 300 and 399.
      # strictly there are only 5 defined
      # 300 Multiple Choices
      # 301 Permanent redirect
      # 302 Temporary redirect
      # 303 See Other
      # 304 Not Modified
      # 305 Must Use Proxy
      # 306 Unused
      # 307 Temporary Redirect
      # 308 Permanent Redirect
      # SEE http://www.restapitutorial.com/httpstatuscodes.html
      def redirect?
        (300..399).includes?(status_code)
      end
    end

    {% for method in %w(get post put head delete patch) %}
      # Executes a {{method.id}} request while following redirects.
      # The response will have its body as a String, accessed via HTTP::Client::Response#body.
      # ```
      # avoids cycling and passes on headers as it sees them
      # limited to maximum number of redirects
      # uses something like CURLOPT_MAXREDIRS to limit
      # Pass a long. The set number will be the redirection limit amount.
      # If that many redirections have been followed, the next redirect
      # will cause an error (CURLE_TOO_MANY_REDIRECTS).
      # This option only makes sense if the CURLOPT_FOLLOWLOCATION is used at the same time.
      #
      # Setting the limit to 0 will make libcurl refuse any redirect.
      # Set it to -1 for an infinite number of redirects.
      # DEFAULT -1, unlimited
      # ```
      # SEE https://curl.haxx.se/libcurl/c/CURLOPT_MAXREDIRS.html
      #
      # ```
      # client = HTTP::Client.new("www.example.com")
      # response = client.{{method.id}}("/", headers: HTTP::Headers{"User-Agent" => "AwesomeApp"}, body: "Hello!")
      # response.body # => "..."
      # ```
      def {{method.id}}(path, headers : HTTP::Headers? = nil, body : BodyType = nil, remaining_redirects = -1) : HTTP::Client::Response
        response = exec {{method.upcase}}, path, headers, body

        if response.redirect?
          raise "Out of Redirects" if remaining_redirects == 0
          remaining_redirects -= 1

          new_path = response.headers["Location"] || response.headers["location"]
          raise "Location not specified" if new_path.nil?

          uri = URI.parse(new_path) # TODO handle relative paths in Location

          cookies = HTTP::Cookies.from_headers(response.headers)
          unless cookies.empty?
	          headers ||= HTTP::Headers.new
            cookies.add_request_headers(headers)
          end

          HTTP::Client.new(uri).{{method.id}}(uri.full_path, headers, body, remaining_redirects)
        else
          response
        end
      end
    {% end %}
  end
end
