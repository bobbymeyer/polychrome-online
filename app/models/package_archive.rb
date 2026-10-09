# frozen_string_literal: true

# A package on disk: a .zip with one JSON file and the pictures (and, for a
# world, the music) it uses under assets/. A campaign module
# (CampaignModule) and a whole world (WorldPackage) travel this way.
#
# Read from an upload, so it's read carefully: only those names, only
# pictures and sound, and a cap on how much it holds. Nothing is written to
# disk; entries are read into memory and attached from there.
class PackageArchive
  IMAGES = %w[png jpg jpeg webp gif].freeze
  SOUNDS = %w[mp3 ogg oga wav m4a].freeze
  KINDS = {
    "polychrome-module" => { data: "module.json", what: "a campaign module", version: 1, files: IMAGES,
                             max_bytes: 60.megabytes, entry_bytes: 15.megabytes },
    "polychrome-world" => { data: "world.json", what: "a world", version: 1, files: IMAGES + SOUNDS,
                            max_bytes: 300.megabytes, entry_bytes: World::MUSIC_MAX_BYTES + 1.megabyte }
  }.freeze
  MAX_ENTRIES = 2000

  # A file in the archive: its name there and its bytes.
  Asset = Data.define(:name, :bytes) do
    def content_type = Marcel::MimeType.for(StringIO.new(bytes), name: name)
  end

  attr_reader :format, :data, :assets

  def initialize(format, data, assets = {})
    @format = format
    @data = data
    @assets = assets
  end

  def self.asset_name?(format, name)
    name.match?(%r{\Aassets/[a-z0-9_-]+\.(#{KINDS.fetch(format)[:files].join('|')})\z})
  end

  def to_zip
    Zip::OutputStream.write_buffer(StringIO.new) do |zip|
      zip.put_next_entry(KINDS.fetch(format)[:data])
      zip.write(JSON.pretty_generate(data))
      assets.each do |name, bytes|
        zip.put_next_entry(name)
        zip.write(bytes)
      end
    end.string
  end

  # The package in an upload (or a String of its bytes), of the format
  # asked for. Refuses what isn't one.
  def self.read(source, format:)
    kind = KINDS.fetch(format)
    bytes = source.respond_to?(:read) ? source.read(kind[:max_bytes] + 1) : source.to_s
    raise Refusal, "That file is too big to be #{kind[:what]} (#{kind[:max_bytes] / 1.megabyte} MB at most)." if bytes.to_s.bytesize > kind[:max_bytes]

    data = nil
    assets = {}
    Zip::File.open_buffer(StringIO.new(bytes)) do |zip|
      raise Refusal, "That file holds too many files to be #{kind[:what]}." if zip.size > MAX_ENTRIES

      zip.each do |entry|
        next if entry.directory?
        raise Refusal, "#{entry.name} in that file is too big." if entry.size > kind[:entry_bytes]

        if entry.name == kind[:data]
          data = JSON.parse(entry.get_input_stream.read(kind[:entry_bytes]))
        elsif asset_name?(format, entry.name)
          assets[entry.name] = Asset.new(name: entry.name, bytes: entry.get_input_stream.read(kind[:entry_bytes]))
        end
      end
    end
    raise Refusal, "That file isn't #{kind[:what]}: it has no #{kind[:data]}." unless data.is_a?(Hash)
    raise Refusal, "That file isn't #{kind[:what]}." unless data["format"] == format
    raise Refusal, "That file was made by a newer version of the game (format #{data['version']})." if data["version"].to_i > kind[:version]

    new(format, data, assets)
  rescue Zip::Error, JSON::ParserError
    raise Refusal, "That file isn't #{kind[:what]} (it isn't a .zip with a #{kind[:data]} in it)."
  end

  # A file from the archive into an attachment slot, when it's the kind the
  # slot takes ("image", "audio"). A name the archive doesn't have is
  # skipped: the slot stays empty, as in a package without art.
  def attach(slot, name, kind: "image")
    asset = name.is_a?(String) && assets[name]
    return unless asset && asset.content_type.start_with?("#{kind}/")

    slot.attach(io: StringIO.new(asset.bytes), filename: File.basename(asset.name), content_type: asset.content_type)
  end
end
