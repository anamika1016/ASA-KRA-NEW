class RenamePaplValuesCultureToAsa < ActiveRecord::Migration[8.0]
  def change
    rename_column :l1_pulse_assessments, :papl_values_culture, :asa_values_culture
  end
end
