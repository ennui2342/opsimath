class RenameWorkTypeToLiteraryFormOnWorks < ActiveRecord::Migration[8.1]
  def change
    rename_column :works, :work_type, :literary_form
  end
end
