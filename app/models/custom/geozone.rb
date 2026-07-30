load Rails.root.join("app", "models", "geozone.rb")

class Geozone < ApplicationRecord

  # --- NEW HIERARCHY ASSOCIATIONS ---
  belongs_to :parent, class_name: "Geozone", optional: true
  has_many :children, class_name: "Geozone", foreign_key: "parent_id", dependent: :nullify
  # ----------------------------------

  # --- NEW HIERARCHY METHODS ---

  # Recursively fetches all children, grandchildren, etc.
  def descendants
    children + children.flat_map(&:descendants)
  end

  # Returns an array of IDs for this zone AND all zones nested inside it
  def self_and_descendant_ids
    [id] + descendants.map(&:id)
  end

  # THE MAGIC CHECK: Returns true if the user's geozone is exactly this one,
  # OR if it is any of the child geozones nested inside it.
  def covers?(other_geozone)
    return false if other_geozone.blank?
    self_and_descendant_ids.include?(other_geozone.id)
  end

  # -----------------------------

  def self.names
    Geozone.pluck(:name)
  end

  def safe_to_destroy?
    # Ensure we don't destroy geozones that still have children
    return false if children.any?

    Geozone.reflect_on_all_associations(:has_many).all? do |association|
      # Skip the children association we just added, as we handled it above
      next true if association.name == :children
      association.klass.where(geozone: self).empty?
    end
  end

end
