class AddCoverArtistToEditions < ActiveRecord::Migration[8.1]
  def change
    add_column :editions, :cover_artist, :string
  end
end
