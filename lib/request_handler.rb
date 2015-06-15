require 'version'

module PhraseApp

  API_CLIENT_IDENTIFIER = "PhraseApp Ruby " + VERSION

  class ErrorResponse
    attr_accessor :message

    def initialize(http_response)
    end

    def error
      self.message
    end
  end

  class ValidationErrorResponse
  	attr_accessor :error_response
    attr_accessor :errors

    def initialize(http_response)
      hash = JSON.load(http_response.body)
      puts hash.inspect
    end

    def errors
      self.error + "\n" + self.errors.join("\n")
    end
  end

  class ValidationErrorMessage
  	attr_accessor :resource, :field, :message

    def to_s
	    return sprintf("\t[%s:%s] %s", self.resource, self.field, self.message)
    end
  end

  class RateLimitingError
    attr_accessor :limit, :remaining, :reset
    
    def initialize(resp)
	  re = RateLimitingError.new(resp)
      puts resp.body.inspect
      re.limit = resp["X-Rate-Limit-Limit"].to_i
	    re.remaining = resp["X-Rate-Limit-Remaining"].to_i
      re.reset = Time.at(resp["X-Rate-Limit-Reset"].to_i)
    	return re, nil
    end
  
    def to_s
	    sprintf("Rate limit exceeded: from %d requests %d are remaning (reset in %d seconds)", self.limit, self.remaining, int64(rle.Reset.Sub(time.Now()).Seconds()))
    end
  end

  def self.multipart(hash)
    hash.inject("") do |res, (k, v)|
      res << "--#{PhraseApp::MULTIPART_BOUNDARY}\r\n"
      res << "Content-Disposition: form-data; name=\"#{k}\"\r\n"
      # res << "Content-Type: #{headers["Content-Type"]}\r\n" if headers["Content-Type"]
      res << "\r\n"
      res << "#{v}\r\n"
      res
    end
  end

  def self.send_request_paginated(method, path_with_query, ctype, body, status, page, per_page)
    uri = URI.parse(path_with_query)

    hash = if uri.query then CGI::parse(uri.query) else {} end
    hash["page"] = page
    hash["per_page"] = per_page
    
    query_str = URI.encode_www_form(hash)
    path = [uri.path, query_str].compact.join('?')

    return send_request(method, path, ctype, body, status)
  end

  def self.send_request(method, path, ctype, data, status)
    req = Net::HTTPGenericRequest.new(method, 
        Module.const_get("Net::HTTP::#{method.capitalize}::REQUEST_HAS_BODY"), 
        Module.const_get("Net::HTTP::#{method.capitalize}::RESPONSE_HAS_BODY"), 
        path)



    puts "data:"
    puts data.inspect
    req.body = data

    if ctype != ""
      req["Content-Type"] = ctype
    end

    resp, err = send(req, status)

    
    return resp, err
  end

  def self.send(req, status)
  	err = PhraseApp::Auth.authenticate(req)
    if err != nil
  		return nil, err
    end

    uri = URI.parse(PhraseApp::URL)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_PEER
    if ENV['DEBUG']
      puts "#{req.method} #{req.path}"
      puts req.body.inspect
      puts "-------"
    end
    resp = http.request(req)

  	err = handleResponseStatus(resp, status)

    return resp, err
  end
  
  def self.handleResponseStatus(resp, expectedStatus)
    case resp.code.to_i
      when expectedStatus
	    	return
      when 400
    		e = ErrorResponse.new(resp)
		    return e
      when 404
    		return raise("not found")
      when 422
    		e = ValidationErrorResponse.new(resp)
		    if e != nil
    			return e
		    end
    		return e
      when 429
		    e, err = RateLimitError.new(resp)
        if err != nil
    			return err
        end
    		return e
      else
		    return raise("unexpected status code (#{resp.code}) received; expected #{expectedStatus}")
    end
  end
end