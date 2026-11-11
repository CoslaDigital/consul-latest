class Layout::SubnavigationComponent < ApplicationComponent; end

load Rails.root.join("app", "components", "layout", "subnavigation_component.rb")

class Layout::SubnavigationComponent
  # We don't need to override any Ruby logic here right now.
  # This file exists solely to tell CONSUL to use our customized
  # HTML view in app/components/custom/layout/subnavigation_component.html.erb
end
