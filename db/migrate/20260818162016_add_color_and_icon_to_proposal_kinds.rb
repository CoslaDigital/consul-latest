class AddColorAndIconToProposalKinds < ActiveRecord::Migration[7.2]
  def change
    add_column :proposal_kinds, :color, :string, default: "#00cae9" # Default Consul blue
    add_column :proposal_kinds, :icon, :string, default: "map-marker-alt" # Default FA icon
  end
end
