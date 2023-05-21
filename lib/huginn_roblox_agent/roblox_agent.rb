module Agents
  class RobloxAgent < Agent
    include FormConfigurable
    can_dry_run!
    no_bulk_receive!
    default_schedule 'every_1h'

    description do
      <<-MD
      The Roblox Agent interacts with Roblox API.

      `debug` is used for verbose mode.

      `details` is used to have conversation's content.

      `userid` is the id of the user.

      `cookie` is mendatory for auth endpoints.

      `type` is for the wanted action like check_friends.

      `expected_receive_period_in_days` is used to determine if the Agent is working. Set it to the maximum number of days
      that you anticipate passing without this Agent receiving an incoming Event.
      MD
    end

    event_description <<-MD
      Events look like this:

          {
            "isOnline": false,
            "isDeleted": false,
            "friendFrequentScore": 0,
            "friendFrequentRank": 1,
            "hasVerifiedBadge": false,
            "description": null,
            "created": "0001-01-01T06:00:00Z",
            "isBanned": false,
            "externalAppDisplayName": null,
            "id": XXXXXXXXXX,
            "name": "XXXXXXXXXXXXXXX",
            "displayName": "XXXXXXXXXXXXXX"
          }
    MD

    def default_options
      {
        'userid' => '',
        'conversationid' => '',
        'message' => '',
        'cookie' => '',
        'type' => 'check_friends',
        'debug' => 'false',
        'details' => 'false',
        'emit_events' => 'true',
        'expected_receive_period_in_days' => '2',
      }
    end

    form_configurable :userid, type: :string
    form_configurable :conversationid, type: :string
    form_configurable :message, type: :string
    form_configurable :cookie, type: :string
    form_configurable :details, type: :boolean
    form_configurable :debug, type: :boolean
    form_configurable :emit_events, type: :boolean
    form_configurable :expected_receive_period_in_days, type: :string
    form_configurable :type, type: :array, values: ['check_friends', 'check_conversations', 'send_message']
    def validate_options
      errors.add(:base, "type has invalid value: should be 'check_friends', 'check_conversations', 'send_message'") if interpolated['type'].present? && !%w(check_friends check_conversations send_message).include?(interpolated['type'])

      unless options['message'].present? || !['send_message'].include?(options['type'])
        errors.add(:base, "message is a required field")
      end

      unless options['conversationid'].present? || !['send_message'].include?(options['type'])
        errors.add(:base, "conversationid is a required field")
      end

      unless options['userid'].present? || !['send_message' 'check_friends'].include?(options['type'])
        errors.add(:base, "userid is a required field")
      end

      unless options['cookie'].present?
        errors.add(:base, "cookie is a required field")
      end

      if options.has_key?('emit_events') && boolify(options['emit_events']).nil?
        errors.add(:base, "if provided, emit_events must be true or false")
      end

      if options.has_key?('details') && boolify(options['details']).nil?
        errors.add(:base, "if provided, details must be true or false")
      end

      if options.has_key?('debug') && boolify(options['debug']).nil?
        errors.add(:base, "if provided, debug must be true or false")
      end

      unless options['expected_receive_period_in_days'].present? && options['expected_receive_period_in_days'].to_i > 0
        errors.add(:base, "Please provide 'expected_receive_period_in_days' to indicate how many days can pass before this Agent is considered to be not working")
      end
    end

    def working?
      event_created_within?(options['expected_receive_period_in_days']) && !recent_error_logs?
    end

    def receive(incoming_events)
      incoming_events.each do |event|
        interpolate_with(event) do
          log event
          trigger_action
        end
      end
    end

    def check
      trigger_action
    end

    private

    def log_curl_output(code,body)

      log "request status : #{code}"

      if interpolated['debug'] == 'true'
        log "body"
        log body
      end

    end

    def get_friends_number()

      uri = URI('https://friends.roblox.com/v1/my/friends/count')
      req = Net::HTTP::Get.new(uri)
      req['Cookie'] = ".ROBLOSECURITY=#{interpolated['cookie']}"
      
      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
        http.request(req)
      end

      log_curl_output(response.code,response.body)

      payload = JSON.parse(response.body)
      return payload

    end

    def get_friends_by_userid()
      uri = URI("https://friends.roblox.com/v1/users/#{interpolated['userid']}/friends")
      req = Net::HTTP::Get.new(uri)
      req['Cookie'] = ".ROBLOSECURITY=#{interpolated['cookie']}"
      
      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
        http.request(req)
      end

      log_curl_output(response.code,response.body)

      payload = JSON.parse(response.body)
      return payload

    end

    def check_friends()
      count = get_friends_number()
      if !memory['count']
        payload = get_friends_by_userid()
        payload['data'].each do |friend|
          if interpolated['emit_events'] == 'true'
            create_event payload: friend
          end
        end
        memory['count'] = count
        memory['friends'] = payload
      else
        if count != memory[:count] and count['count'] > memory['count']['count']
          if payload != memory['friends']
            if memory['friends'] == ''
            else
              last_status = memory['last_status']
              payload['data'].each do |friend|
                found = false
                if interpolated['debug'] == 'true'
                  log "friend"
                  log friend
                end
                last_status['friends']['data'].each do |friendbis|
                  if friend['id'] == friendbis['id']
                    found = true
                  end
                  if interpolated['debug'] == 'true'
                    log "friendbis"
                    log friendbis
                    log "found is #{found}!"
                  end
                end
                if found == false
                  create_event payload: friend
                end
              end
            end
            memory['friends'] = payload
          end
          memory['count'] = count
        else
          if interpolated['debug'] == 'true'
            log "nothing to compare because same count"
          end
        end
      end  
    end

    def get_conversations(id)
      uri = URI("https://chat.roblox.com/v2/get-messages?conversationId=#{id}&pageSize=100")
      req = Net::HTTP::Get.new(uri)
      req['Cookie'] = ".ROBLOSECURITY=#{interpolated['cookie']}"
      
      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
        http.request(req)
      end

      log_curl_output(response.code,response.body)

      return response.body

    end

    def check_conversations()
      uri = URI("https://chat.roblox.com/v2/get-user-conversations?pageNumber=1&pageSize=10")
      req = Net::HTTP::Get.new(uri)
      req['Cookie'] = ".ROBLOSECURITY=#{interpolated['cookie']}"

      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
        http.request(req)
      end

      log_curl_output(response.code,response.body)

      payload = JSON.parse(response.body)
      if !memory['conversations']
        payload.each do |conversation|
          if interpolated['details'] == 'true'
            conversation['details_content'] = []
            JSON.parse(get_conversations(conversation['id'])).each do |line|
              userid = conversation['participants'].find { |p| p['targetId'] == line['senderTargetId'] }
              newline = "#{line['sent']} #{userid['name']} : #{line['content']}"
              conversation['details_content'] << newline
            end
          end
          if interpolated['emit_events'] == 'true'
            create_event payload: conversation
          end
        end
        memory['conversations'] = payload
      else
        last_status = memory['conversations']
        payload.each do |conversation|
          found = false
          if interpolated['debug'] == 'true'
            log "conversation"
            log conversation
          end
          last_status.each do |conversationbis|
            if conversation['id'] == conversationbis['id'] && DateTime.parse(conversation['lastUpdated']).strftime("%Y-%m-%dT%H:%M:%S") == DateTime.parse(conversationbis['lastUpdated']).strftime("%Y-%m-%dT%H:%M:%S")
              found = true
            end
            if interpolated['debug'] == 'true'
              log "conversationbis"
              log conversationbis
              log "found is #{found}!"
            end
          end
          if found == false
            if interpolated['details'] == 'true'
              conversation['details_content'] = []
              date1 = last_status.find { |conversationter| conversationter["id"] == conversation['id'] }
              if !date1.nil?
                date1 = DateTime.parse(date1['lastUpdated'])
                log "testbis"
                JSON.parse(get_conversations(conversation['id'])).each do |line|
                  date2 = DateTime.parse(line['sent'])
                  userid = conversation['participants'].find { |p| p['targetId'] == line['senderTargetId'] }
                  newline = "#{line['sent']} #{userid['name']} : #{line['content']}"
                  if date1 < date2
                    conversation['details_content'] << newline
                  end
                end
              end
            end
            create_event payload: conversation
          end
        end
        memory['conversations'] = payload
      end  
    end

    def send_message()
      uri = URI.parse("https://chat.roblox.com/v2/send-message")
      request = Net::HTTP::Post.new(uri)
      request.content_type = "application/json"
      request["Accept"] = "application/json"
      request.body = JSON.dump({
        "message" => interpolated['message'],
        "isExperienceInvite" => true,
        "userId" => interpolated['userid'],
        "conversationId" => interpolated['conversationid'],
        "decorators" => [
          "string"
        ]
      })

      req_options = {
        use_ssl: uri.scheme == "https",
      }

      response = Net::HTTP.start(uri.hostname, uri.port, req_options) do |http|
        http.request(request)
      end

      log_curl_output(response.code,response.body)

      if interpolated['emit_events'] == 'true'
        create_event payload: response.body
      end

    end

    def trigger_action

      case interpolated['type']
      when "check_friends"
        check_friends()
      when "check_conversations"
        check_conversations()
      when "send_message"
        send_message()
      else
        log "Error: type has an invalid value (#{interpolated['type']})"
      end
    end
  end
end
