# app/lib/import_propositions.rb
require 'csv'

def import_propositions_to_legislation(csv_path)
  # 1. Force the database translation context to UK English
  I18n.locale = :'en-GB'

  # 2. Grab a valid administrative account to set as the author anchor
  admin_user = User.administrators.first
  if admin_user.nil?
    puts "❌ ERROR: No administrative user found in the database. Please seed an admin user first."
    return
  end

  puts "🚀 Initialising Jigsaw Proposition Import Matrix (UK English Locale)..."
  puts "📂 Target CSV Path: #{csv_path}"

  unless File.exist?(csv_path)
    puts "❌ ERROR: File target not found at: #{csv_path}"
    puts "💡 Please check your relative path or absolute path string and try again."
    return
  end

  # 3. Instantiate the parent process model parameters as a private DRAFT
  process_title = "DRAFT: Community Safety Sensemaking Consultation — #{Date.current.strftime('%B %Y')}"

  process = Legislation::Process.new(
    title: process_title,
    summary: "A data-driven legislative review process automatically constructed from citizen text comments and town hall submissions.",
    description: "This consultation presents the top-ranked policy propositions distilled via natural language modelling. Citizens are invited to debate and vote on each proposition block below.",
    start_date: Date.current,
    end_date: Date.current + 30.days,

    # Keeps the process private and hidden from the public index pages
    published: false,

    # Spins up and isolates the specific Draft Phase timelines
    draft_start_date: Date.current,
    draft_end_date: Date.current + 30.days,
    draft_phase_enabled: true,

    # Keep forward-facing public interaction pathways turned off during staging
    debate_phase_enabled: false,
    proposals_phase_enabled: false,
    allegations_phase_enabled: false
  )

  unless process.save
    puts "❌ ERROR: Failed to instantiate parent Legislation::Process: #{process.errors.full_messages.join(', ')}"
    return
  end
  puts "✅ Created DRAFT Legislation::Process [ID: #{process.id}] -> '#{process.title}'"

  # 4. Loop over elements inside our final output spreadsheet file
  question_counter = 0

  CSV.foreach(csv_path, headers: true) do |row|
    proposition_text = row['proposition']
    topic_tag = row['topic']
    consensus_metric = row['approval_rate']

    next if proposition_text.blank?

    # 5. Build individual matching Legislation::Question entities with UK terminology
    question_description = "### Context Tracking\n" \
      "* **Thematic Category Group:** #{topic_tag}\n" \
      "* **AI Consensus Score:** #{consensus_metric}\n\n" \
      "Please declare your stance on this policy proposition by selecting a preferred option below. " \
      "You may add clarifying text arguments or structural counter-arguments in the discussion thread below."

    question = Legislation::Question.new(
      legislation_process_id: process.id,
      author_id: admin_user.id,
      title: proposition_text.strip,
      description: question_description
    )

    unless question.save
      puts "⚠️ WARNING: Skipping question generation row due to validation fault: #{question.errors.full_messages.join(', ')}"
      next
    end

    # 6. Seed the structured survey choices using standard British public polling variants
    ["In Favour / Agree", "Against / Disagree", "Abstain / Undecided"].each do |option_label|
      Legislation::QuestionOption.create!(
        legislation_question_id: question.id,
        value: option_label
      )
    end

    question_counter += 1
    puts "   ➔ Successfully appended Question #{question_counter}: '#{proposition_text[0..45]}...'"
  end

  puts "🎉 PIPELINE COMPLETE: #{question_counter} staging questions integrated into Draft Process ID ##{process.id}."
end

# --- CLI ARGUMENT PARSER CHECK ---
# ARGV[0] captures the first text parameter passed after the script name
target_path = ARGV[0]

if target_path.blank?
  puts "❌ ERROR: Missing target path argument."
  puts "💡 Usage: ./bin/rails runner app/lib/import_propositions.rb <PATH_TO_CSV>"
else
  import_propositions_to_legislation(target_path)
end
