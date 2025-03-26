class AddModelEndpointToLlmVendors < ActiveRecord::Migration[7.0]
  def change
    add_column :llm_vendors, :model_endpoint, :string
  end
end
