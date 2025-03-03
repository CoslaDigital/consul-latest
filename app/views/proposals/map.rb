<div class="row">
  <div class="small-12 medium-9 column margin-top">

    <h1><%= t("map.title") %></h1>

    <div class="row">
      <div class="small-12 medium-3 column">
        <ul id="geozones" class="no-bullet">
          <% @geozones.each do |geozone| %>
            <li><%= link_to geozone.name, proposals_path(search: geozone.name) %></li>
          <% end %>
        </ul>
      </div>
   
      <%= render Shared::MapLocationComponent.new(nil, geozones_data: geozones_data) %>
    </div>
    <h2><%= t("map.proposal_for_district") %></h2>

    <%= form_for(@proposal, url: new_proposal_path, method: :get) do |f| %>
      <div class="small-12 medium-4">
        <%= f.select :geozone_id, geozone_select_options, include_blank: t("geozones.none") %>
      </div>

      <div class="actions small-12">
        <%= f.submit(class: "button radius", value: t("map.start_proposal")) %>
      </div>
    <% end %>
  </div>

  <div class="small-12 medium-3 column">
    <aside class="sidebar">
      <%= link_to t("map.start_proposal"),
                  new_proposal_path, class: "button radius expand" %>
      <%= render "shared/tag_cloud", taggable: "Proposal" %>
    </aside>
  </div>
</div>