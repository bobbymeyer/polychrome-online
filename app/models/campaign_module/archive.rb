# frozen_string_literal: true

# A module on disk: a .zip with module.json and the pictures it uses
# under assets/. Read from an upload, so it's read carefully: only those
# names, pictures only, and a cap on how much it can hold. Nothing is
# written to disk; entries are read into memory and attached from there.
module CampaignModule
  class Archive
    DATA = "module.json"
    ASSET = %r{\Aassets/[a-z0-9_-]+\.(png|jpe?g|webp|gif)\z}
    MAX_BYTES = 60.megabytes
    MAX_ENTRY_BYTES = 15.megabytes
    MAX_ENTRIES = 1000

    # A picture in the archive: its name there and its bytes.
    Asset = Data.define(:name, :bytes) do
      def content_type = Marcel::MimeType.for(StringIO.new(bytes), name: name)
    end

    attr_reader :data, :assets

    def initialize(data, assets = {})
      @data = data
      @assets = assets
    end

    def to_zip
      Zip::OutputStream.write_buffer(StringIO.new) do |zip|
        zip.put_next_entry(DATA)
        zip.write(JSON.pretty_generate(data))
        assets.each do |name, bytes|
          zip.put_next_entry(name)
          zip.write(bytes)
        end
      end.string
    end

    # The archive in an upload (or a String of its bytes). Refuses what
    # isn't a module.
    def self.read(source)
      bytes = source.respond_to?(:read) ? source.read(MAX_BYTES + 1) : source.to_s
      raise Refusal, "That file is too big to be a module (#{MAX_BYTES / 1.megabyte} MB at most)." if bytes.to_s.bytesize > MAX_BYTES

      data = nil
      assets = {}
      Zip::File.open_buffer(StringIO.new(bytes)) do |zip|
        raise Refusal, "That module holds too many files." if zip.size > MAX_ENTRIES

        zip.each do |entry|
          next if entry.directory?
          raise Refusal, "#{entry.name} in the module is too big." if entry.size > MAX_ENTRY_BYTES

          if entry.name == DATA
            data = JSON.parse(entry.get_input_stream.read(MAX_ENTRY_BYTES))
          elsif entry.name.match?(ASSET)
            assets[entry.name] = Asset.new(name: entry.name, bytes: entry.get_input_stream.read(MAX_ENTRY_BYTES))
          end
        end
      end
      raise Refusal, "That file isn't a campaign module: it has no #{DATA}." unless data.is_a?(Hash)
      raise Refusal, "That file isn't a campaign module." unless data["format"] == FORMAT
      raise Refusal, "That module was made by a newer version of the game (format #{data['version']})." if data["version"].to_i > VERSION

      new(data, assets)
    rescue Zip::Error, JSON::ParserError
      raise Refusal, "That file isn't a campaign module (it isn't a .zip with a #{DATA} in it)."
    end
  end
end
