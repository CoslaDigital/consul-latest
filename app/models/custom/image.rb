load Rails.root.join("app", "models", "image.rb")

class Image < ApplicationRecord

  def self.styles
    {
      
      hero_small:  { gravity: "center", resize: "768x", crop: "768x192+0+0" },
      hero_medium: { gravity: "center", resize: "1280x", crop: "1280x320+0+0" },
      hero_large:  { gravity: "center", resize: "1920x", crop: "1920x480+0+0" },
      hero:        { gravity: "center", resize: "2816x", crop: "2816x704+0+0" },
      larger: { resize: "1920x" },
      large: { resize: "x#{Setting["uploads.images.min_height"]}" },
      medium: { gravity: "center", resize: "300x300^", crop: "300x300+0+0" },
      thumb: { gravity: "center", resize: "140x245^", crop: "140x245+0+0" }
    }
  end

end
