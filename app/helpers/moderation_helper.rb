module ModerationHelper
  
  def handle_moderation(moderatable, moderation_result)
      if moderation_result[:flagged]
        moderatable.update(flags_count: moderation_result[:flags])
      end

      if moderation_result[:hidden] || moderation_result[:flags] > thresh
        moderatable.update(hidden_at: Time.current)
      end
    end


  def moderate_text(text)
    is_flagged = false
    is_hidden = false
    flag_score = 0
    flag_cat = ""
    
    vendor = Setting.get_vendor_name
    if vendor == "Moderation API"
  puts "WTD"
else
  puts "NO NO NO"
end
    api_key = Setting.get_vendor_api
    puts "THE VENDOR IS #{vendor.inspect}"
    thresh = Rails.application.secrets.openai_thresh || 1.5
    #openai_key = Rails.application.secrets.openai_key

    # Test code to avoid using OpenAI
    if text == "Bad Bad Bad Comment"
      is_flagged = true
      flag_score = 300
    elsif api_key && !api_key.strip.empty?
      case vendor
      when "Moderation API"
        puts "inside Moderation Case"
        response = moderation_api_moderate(text, api_key)
        is_hidden = response[:hidden]
        is_flagged = response[:flagged]
        flag_score = response[:flags] || 0
        flag_cat = response[:category]
      when "OpenAI"
        response = openaimoderate(text, api_key)
        is_hidden = response[:hidden]
        is_flagged = response[:flagged]
        flag_score = response[:flags] || 0
        flag_cat = response[:category]
     # Add more vendors here as needed
      else
        puts "Unsupported vendor: #{vendor}"
      end
    end
    
    { hidden: is_hidden, flagged: is_flagged, flags: flag_score, category: flag_cat }
  end

  def openaimoderate(text_string, api_key)
    thresh = Rails.application.secrets.openai_thresh || 1.5
    puts "insideopenaimoderate #{api_key}"
    # openai_key = Rails.application.secrets.openai_key
    is_hidden = false
    is_flagged = false
    flag_score = 0
    flag_cat = {}

    return { hidden: is_hidden, flagged: is_flagged, flags: flag_score, category: "missing api key" } if api_key.nil?

    client = OpenAI::Client.new(access_token: api_key) rescue nil
    return { hidden: is_hidden, flagged: is_flagged, flags: flag_score, category: "client initialization error" } if client.nil?

    response = client.moderations(parameters: { model: "omni-moderation-latest", input: text_string }) rescue nil
    if response.body.nil? || response.body.empty? || response.to_s.include?("error")
      error_message = response["error"]["message"] rescue "Unknown error"
      error_code = response["error"]["code"] rescue "unknown_error"
      return { hidden: is_hidden, flagged: is_flagged, flags: flag_score, category: "API error: #{error_code}", message: error_message }
    end

    is_hidden = response["results"][0]["flagged"] == true
    scores = response["results"][0]["category_scores"]
    total_score = 0

    scores.each do |cat, score|
      total_score += score
      if score > thresh
        flag_score += 2
      #  flag_cat += cat
        flag_cat[cat] = score
      end
    end
    is_flagged = flag_score > thresh

    { hidden: is_hidden, flagged: is_flagged, flags: flag_score, category: flag_cat }
  end
  
def moderation_api_moderate(text_string, api_key)
  thresh = Rails.application.secrets.openai_thresh || 1.5
  puts "inside moderation_api_moderate #{api_key}"
  
  is_hidden = false
  is_flagged = false
  flag_score = 0
  flag_cat = {}
  profanity_matches = []

  return { hidden: is_hidden, flagged: is_flagged, flags: flag_score, category: "missing api key" } if api_key.nil?

  ModerationApi.configure do |config|
    config.access_token = api_key
  end

  api = ModerationApi::ModerateApi.new

  text_request = ModerationApi::ModerationTextRequest.new(
    value: text_string,
    author_id: "123",
    context_id: "456",
    metadata: {
      custom_field: "value"
    }
  )

  begin
    response = api.moderation_text(text_request)
    
    if response.flagged
      is_hidden = true
      flag_score += 2
      flag_cat["flagged"] = response.flagged
    end

    scores = {}
    if response.toxicity
      scores.merge!(
        toxicity: response.toxicity.label_scores.toxicity,
        profanity: response.toxicity.label_scores.profanity,
        discrimination: response.toxicity.label_scores.discrimination,
        severe_toxicity: response.toxicity.label_scores.severe_toxicity,
        insult: response.toxicity.label_scores.insult,
        threat: response.toxicity.label_scores.threat,
        neutral: response.toxicity.label_scores.neutral
      )
    end
    if response.nsfw
      scores.merge!(
        unsafe: response.nsfw.label_scores.unsafe,
        neutral: response.nsfw.label_scores.neutral
      )
    end
    if response.sentiment
      scores.merge!(
        positive: response.sentiment.label_scores.positive,
        negative: response.sentiment.label_scores.negative,
        neutral: response.sentiment.label_scores.neutral
      )
    end

    if response.profanity && response.profanity.found
      profanity_matches = response.profanity.matches
    end

    total_score = scores.values.sum

    puts "Scores returned:"
    scores.each do |cat, score|
      puts "#{cat}: #{score}"
      if score > thresh
        flag_score += score
        flag_cat[cat] = score
      end
    end

    is_flagged = flag_score > thresh

    { hidden: is_hidden, flagged: is_flagged, flags: flag_score, category: flag_cat, profanity_matches: profanity_matches }
  rescue ModerationApi::ApiError => e
    error_message = e.message || "Unknown error"
    error_code = e.code || "unknown_error"
    { hidden: is_hidden, flagged: is_flagged, flags: flag_score, category: "API error: #{error_code}", message: error_message }
  end
end
end