# db/seeds/ys_elections.rb

puts "🚀 Initializing Local Authority Elections & Geozones for #{Time.current.year}..."

# Comprehensive mapping of Local Authorities to their Scottish Parliamentary Constituencies
AUTHORITY_CONSTITUENCIES = {
  "aberdeen_city" => ["Aberdeen Central", "Aberdeen Donside", "Aberdeen South and North Kincardine"],
  "aberdeenshire" => ["Aberdeenshire East", "Aberdeenshire West", "Banffshire and Buchan Coast"],
  "angus" => ["Angus North and Mearns", "Angus South"],
  "argyll_and_bute" => ["Argyll and Bute"],
  "city_of_edinburgh" => ["Edinburgh Central", "Edinburgh Eastern", "Edinburgh Northern and Leith", "Edinburgh Pentlands", "Edinburgh Southern", "Edinburgh Western"],
  "clackmannanshire" => ["Clackmannanshire and Dunblane"],
  "western_isles" => ["Na h-Eileanan an Iar"],
  "dumfries_and_galloway" => ["Dumfriesshire", "Galloway and West Dumfries"],
  "dundee_city" => ["Dundee City East", "Dundee City West"],
  "east_ayrshire" => ["Carrick, Cumnock and Doon Valley", "Kilmarnock and Irvine Valley"],
  "east_dunbartonshire" => ["Clydebank and Milngavie", "Strathkelvin and Bearsden"],
  "east_lothian" => ["East Lothian"],
  "east_renfrewshire" => ["Eastwood", "Renfrewshire South"],
  "falkirk" => ["Falkirk East", "Falkirk West"],
  "fife" => ["Cowdenbeath", "Dunfermline", "Kirkcaldy", "Mid Fife and Glenrothes", "North East Fife"],
  "glasgow_city" => ["Glasgow Anniesland", "Glasgow Cathcart", "Glasgow Kelvin", "Glasgow Maryhill and Springburn", "Glasgow Pollok", "Glasgow Provan", "Glasgow Shettleston", "Glasgow Southside"],
  "highland" => ["Caithness, Sutherland and Ross", "Inverness and Nairn", "Skye, Lochaber and Badenoch"],
  "inverclyde" => ["Greenock and Inverclyde"],
  "midlothian" => ["Midlothian North and Musselburgh", "Midlothian South"],
  "moray" => ["Moray"],
  "north_ayrshire" => ["Cunninghame North", "Cunninghame South"],
  "north_lanarkshire" => ["Airdrie and Shotts", "Coatbridge and Chryston", "Cumbernauld and Kilsyth", "Motherwell and Wishaw", "Uddingston and Bellshill"],
  "orkney_islands" => ["Orkney"],
  "perth_and_kinross" => ["Perthshire North", "Perthshire South and Kinross-shire"],
  "renfrewshire" => ["Paisley", "Renfrewshire North and West"],
  "scottish_borders" => ["Ettrick, Roxburgh and Berwickshire", "Midlothian South, Tweeddale and Lauderdale"],
  "shetland_islands" => ["Shetland"],
  "south_ayrshire" => ["Ayr"],
  "south_lanarkshire" => ["Clydesdale", "East Kilbride", "Hamilton, Larkhall and Stonehouse", "Rutherglen"],
  "stirling" => ["Stirling"],
  "west_dunbartonshire" => ["Dumbarton"],
  "west_lothian" => ["Almond Valley", "Linlithgow"],
  "trumptonshire" => ["Trumpton Central", "Chigley", "Camberwick Green"]
}.freeze

ActiveRecord::Base.transaction do
  current_year = Time.current.year

  AUTHORITY_CONSTITUENCIES.each do |la_name, constituencies|
    formatted_la_name = la_name.titleize
    geozone_name = "ys_#{la_name}"

    # 1. Create or Find the Geozone
    geozone = Geozone.find_or_create_by!(name: geozone_name) do |g|
      puts "   📍 Created new Geozone: #{geozone_name}"
    end

    # 2. Safely Find or Create the Budget dynamically by year
    budget_name = "#{current_year} #{formatted_la_name} Elections"
    budget = Budget.joins(:translations).where(budget_translations: { name: budget_name, locale: I18n.locale }).first

    unless budget
      budget = Budget.create!(
        name: budget_name,
        phase: "informing", # <-- The actual earliest phase in Consul
        published: false, # <-- This makes it a "Draft"
        kind: "election",
        voting_style: "approval",
        currency_symbol: "£",
        hide_money: true,
        stv: true,
        stv_dynamic_quota: true
      )
    end

    # 3. Safely Find or Create the Group
    group = budget.groups.joins(:translations).where(budget_group_translations: { name: "Parliamentary Constituencies", locale: I18n.locale }).first
    unless group
      group = Budget::Group.create!(
        name: "Parliamentary Constituencies",
        budget: budget,
        max_votable_headings: 1
      )
    end

    # 4. Safely Find or Create the Headings
    constituencies.each do |constituency|
      heading = group.headings.joins(:translations).where(budget_heading_translations: { name: constituency, locale: I18n.locale }).first

      unless heading
        heading = Budget::Heading.new(
          name: constituency,
          group: group,
          price: 1_000_000,
          max_winners: 3
        )

        # Restrict the heading to the specific ys_ geozone
        if heading.respond_to?(:geozone_id=)
          heading.geozone_id = geozone.id
        end

        heading.save!
      end
    end

    puts "✅ Created/Verified Draft Election for #{formatted_la_name} with #{constituencies.count} constituencies."
  end

  puts "---------------------------------------------------"
  puts "🎉 Seeding Complete! All #{AUTHORITY_CONSTITUENCIES.count} Authority elections are drafted for #{current_year} and linked to ys_ geozones."
end
