module ModerationHelper
  def moderate_text(text)
    is_flagged = false
    is_hidden = false
    flag_score = 0
    flag_cat = ""

    thresh = Rails.application.secrets.openai_thresh || 1.5
    openai_key = Rails.application.secrets.openai_key

    # Test code to avoid using OpenAI
    if text == "Bad Bad Bad Comment"
      is_flagged = true
      flag_score = 300
    elsif openai_key && !openai_key.strip.empty?
      response = openaimoderate(text)
      is_hidden = response[:hidden]
      is_flagged = response[:flagged]
      flag_score = response[:flags] || 0
      flag_cat = response[:category]
    end

    { hidden: is_hidden, flagged: is_flagged, flags: flag_score, category: flag_cat }
  end

  def openaimoderate(text_string)
    thresh = Rails.application.secrets.openai_thresh || 1.5
    openai_key = Rails.application.secrets.openai_key
    is_hidden = false
    is_flagged = false
    flag_score = 0
    flag_cat = ""

    return { hidden: is_hidden, flagged: is_flagged, flags: flag_score, category: "missing api key" } if openai_key.nil? || openai_key.strip.empty?

    client = OpenAI::Client.new(access_token: openai_key) rescue nil
    return { hidden: is_hidden, flagged: is_flagged, flags: flag_score, category: "client initialization error" } if client.nil?

    response = client.moderations(parameters: { model: "omni-moderation-latest", input: text_string }) rescue nil
    if response.nil? || response.to_s.include?("error")
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
        flag_cat += cat
      end
    end
    is_flagged = flag_score > thresh

    { hidden: is_hidden, flagged: is_flagged, flags: flag_score, category: flag_cat }
  end
end