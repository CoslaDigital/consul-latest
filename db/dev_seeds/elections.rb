# frozen_string_literal: true
require 'open-uri'

# --- 1. CONSUL HELPER METHODS ---
def section(title)
  puts "\n=== #{title} ==="
  yield
end

def random_locales
  [I18n.default_locale, I18n.available_locales.sample].uniq
end

def random_locales_attributes(attributes)
  random_locales.each_with_object({}) do |locale, result|
    attributes.each do |attribute, value|
      result["#{attribute}_#{locale.to_s.underscore}"] = value.is_a?(Proc) ? value.call : value
    end
  end
end

def add_image_to_investment(investment, candidate_name)
  url = "https://robohash.org/#{URI.encode_www_form_component(candidate_name)}.png?set=set5&size=500x500"

  begin
    downloaded_image = URI.open(url)

    investment.image = Image.create!(
      imageable: investment,
      attachment: {
        io: downloaded_image,
        filename: "#{candidate_name.parameterize}.png",
        content_type: 'image/png'
      },
      title: "Campaign photo of #{candidate_name}"
    )
  rescue StandardError => e
    puts "  [!] Could not generate image for #{candidate_name}: #{e.message}"
  end
end

# --- 2. PRE-RUN CLEANUP ---
section "Cleaning up old data" do
  old_elections = Budget.with_translations.where(budget_translations: { name: "Trumptonshire Test Election 2026" })
  if old_elections.any?
    puts "Destroying #{old_elections.count} old Trumptonshire election(s) to start fresh..."
    old_elections.destroy_all
  else
    puts "No old elections found. Ready to proceed!"
  end
end

# --- 3. ELECTION GENERATION ---
section "Creating Trumptonshire Election" do
  puts "Creating the Election Budget..."

  author = User.find_by(email: "admin@trumptonshire.gov.uk") || User.create!(
    username: "Electoral_Officer", email: "admin@trumptonshire.gov.uk",
    password: "password", terms_of_service: "1", confirmed_at: Time.current
  )

  election = Budget.create!(
    {
      kind: "election",
      voting_style: "approval",
      stv: true,
      stv_winners: 3,
      stv_dynamic_quota: false,
      currency_symbol: "£",
      phase: "finished",
      published: true
    }.merge(random_locales_attributes(name: -> { "Trumptonshire Test Election 2026" }))
  )

  puts "Creating Trumptonshire Group & Constituencies..."

  group = election.groups.create!(
    random_locales_attributes(name: -> { "Trumptonshire" })
  )

  headings_data = [
    { name: "Trumpton", population: 8000, seats: 3, lines: 5 },
    { name: "Camberwick Green", population: 5000, seats: 2, lines: 4 },
    { name: "Chigley", population: 6000, seats: 2, lines: 4 }
  ]

  headings = {}
  headings_data.each do |data|
    heading = group.headings.create!(
      {
        price: 0,
        population: data[:population],
        max_winners: data[:seats],
        max_ballot_lines: data[:lines]
      }.merge(random_locales_attributes(name: -> { data[:name] }))
    )
    headings[data[:name]] = heading
  end

  puts "Creating Candidates (Investments) and generating RoboHash avatars..."

  candidates_data = {
    "Trumpton" => [
      { name: "The Mayor of Trumpton", summary: "A steady hand on the clock tower.", description: "<p>I promise to keep the town clock accurate, ensure the town hall steps are clean, and keep the fire brigade well-funded for retrieving hats from trees. Vote for stability!</p>" },
      { name: "Captain Flack", summary: "Fire Brigade Captain.", description: "<p>Pugh, Pugh, Barney McGrew, Cuthbert, Dibble, Grub! Fire safety is my absolute priority. Furthermore, I pledge to hold band practice at the bandstand every Wednesday without fail.</p>" },
      { name: "Mr. Troop", summary: "The Town Clerk.", description: "<p>Bureaucracy done right. I will make sure all forms are filed in triplicate, all permits are processed correctly, and Trumpton runs like a well-oiled machine.</p>" },
      { name: "Chippy Minton", summary: "Local Carpenter.", description: "<p>Fixing our infrastructure, one plank at a time. I'll make sure the bridges are sturdy and the benches in the park are comfortable for all residents.</p>" },
      { name: "Mrs. Cobbit", summary: "Town Florist.", description: "<p>Making Trumpton beautiful. A flower in every window! I promise to expand the public gardens and support local high street businesses.</p>" }
    ],
    "Camberwick Green" => [
      { name: "Windy Miller", summary: "Local Miller and Cider Enthusiast.", description: "<p>Sustainable wind power for all! I support local agriculture, organic stone-ground flour, and a good drop of homemade cider after a hard day's work.</p>" },
      { name: "Dr. Mopp", summary: "Town Doctor.", description: "<p>Keeping everyone healthy. My vintage car ensures I get to house calls in style. I pledge shorter waiting times for appointments and free lollipops for brave patients.</p>" },
      { name: "Peter Hazel", summary: "Postman.", description: "<p>Reliable communication. Rain or shine, the mail gets delivered. I promise to support the postal service and ensure parcels are handled with care.</p>" },
      { name: "PC McGarry", summary: "Local Bobby.", description: "<p>Law and order with a friendly face. Number 452, at your service! I'll keep the streets safe, deal with stray dogs, and make sure bicycles are roadworthy.</p>" },
      { name: "Captain Snort", summary: "Pippin Fort Commander.", description: "<p>Discipline and drill! We will march into a brighter future. I pledge to maintain the fort to the highest standards and promote fitness in the community.</p>" }
    ],
    "Chigley" => [
      { name: "Lord Belborough", summary: "Owner of the Winkstead Hall Estate.", description: "<p>Philanthropy and heritage. I will continue to run the narrow-gauge railway for the benefit of the community and open the estate gardens on weekends.</p>" },
      { name: "Mr. Cresswell", summary: "Biscuit Factory Owner.", description: "<p>Economic growth through biscuits! I promise employment for the masses, high-quality baked goods, and of course, a 6 o'clock factory dance for all workers.</p>" },
      { name: "Mr. Brackett", summary: "Chauffeur and Butler.", description: "<p>Service with a smile. I ensure things run smoothly behind the scenes. If you want a councillor who understands hard work and punctuality, look no further.</p>" },
      { name: "Winnie Farthing", summary: "Biscuit Maker.", description: "<p>Representing the workers! I stand for fair wages, safer factory floors, and better tea breaks on the biscuit production line.</p>" },
      { name: "Harry Farthing", summary: "Local Potter.", description: "<p>Supporting local artisans. Clay, wheels, and creativity. I promise to fund local arts programs and keep Chigley's traditional crafts alive.</p>" }
    ]
  }

  candidates_data.each do |heading_name, candidates|
    heading = headings[heading_name]
    puts "  -> Spawning candidates for #{heading_name}..."

    candidates.each do |candidate|
      # Only translate title and description
      translation_attributes = random_locales.each_with_object({}) do |locale, attributes|
        attributes["title_#{locale.to_s.underscore}"] = candidate[:name]
        attributes["description_#{locale.to_s.underscore}"] = candidate[:description]
      end

      investment = Budget::Investment.create!({
                                                author: author,
                                                heading: heading,
                                                group: heading.group,
                                                budget: election,
                                                summary: candidate[:summary], # Passed as a regular column
                                                created_at: rand((1.week.ago)..Time.current),
                                                feasibility: "feasible",
                                                valuation_finished: true,
                                                selected: true,
                                                price: 0,
                                                terms_of_service: "1"
                                              }.merge(translation_attributes))

      add_image_to_investment(investment, candidate[:name])
    end
  end

  puts "✅ Trumptonshire Test Election Generated Successfully!"
  puts "Now you can vote using the frontend, or go to Admin -> Budgets to calculate winners!"
end
