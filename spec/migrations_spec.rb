# frozen_string_literal: true

# Removing or changing a column rebuilds the table in SQLite, and inside a
# transaction SQLite can't switch foreign keys off, so the rebuild fires
# ON DELETE actions on other tables: a character's choice picks cascaded
# away, a front secret lost its person. A migration that rebuilds a table
# runs outside a transaction, where Rails switches them off.
RSpec.describe "Migrations" do
  REBUILDS = /\b(remove_column|remove_reference|remove_belongs_to|change_column|rename_column|change_column_null|change_column_default|remove_timestamps)\b/
  SINCE = 20260929040000 # the first one written after this was learned the hard way

  Dir[File.expand_path("../db/migrate/*.rb", __dir__)].sort.each do |path|
    version = File.basename(path).to_i
    source = File.read(path)
    next unless version >= SINCE && source.match?(REBUILDS)

    it "#{File.basename(path)} rebuilds a table outside a transaction" do
      expect(source).to include("disable_ddl_transaction!")
    end
  end
end
