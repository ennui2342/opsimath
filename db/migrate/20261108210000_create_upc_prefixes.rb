# What a US mass-market paperback's UPC publisher code means as an ISBN
# prefix (UpcLookup): there's no published table, so it's learnt from
# scans — each scan's candidate prefixes narrow the set until one is left.
class CreateUpcPrefixes < ActiveRecord::Migration[8.1]
  def change
    create_table :upc_prefixes do |t|
      t.string :manufacturer, null: false, index: { unique: true } # UPC digits 2-6
      t.string :candidates, array: true, null: false, default: []  # ISBN-10 first 4 digits still possible
      t.string :prefix                                            # once only one is left
      t.timestamps
    end
  end
end
