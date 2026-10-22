# frozen_string_literal: true

# A package on disk: a .zip with one JSON file and the pictures (and, for a
# world, the music) it uses under assets/. A campaign module
# (CampaignModule) and a whole world (WorldPackage) travel this way.
#
# Read from an upload, so it's read carefully: only those names, only
# pictures and sound (by what their bytes are, not their names), and caps on
# what it holds: entries, each entry, and all of it unpacked (a few hundred
# kilobytes of zip can unpack to gigabytes). Nothing is written to disk;
# entries are read into memory and attached from there.
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
  # The names a package may hold pictures and sound under, one pattern a format, built once.
  ASSET_NAMES = KINDS.transform_values { |kind| %r{\Aassets/[a-z0-9_-]+\.(?:#{kind[:files].join('|')})\z} }.freeze
  # What a slot takes, by what the bytes are (Marcel): an SVG named .png is
  # an SVG, and isn't a picture here.
  CONTENT_TYPES = {
    "image" => %w[image/png image/jpeg image/webp image/gif],
    "audio" => %w[audio/mpeg audio/ogg audio/x-wav audio/wav audio/mp4 audio/x-m4a]
  }.freeze

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
    name.match?(ASSET_NAMES.fetch(format))
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
    unpacked = 0
    Zip::File.open_buffer(StringIO.new(bytes)) do |zip|
      raise Refusal, "That file holds too many files to be #{kind[:what]}." if zip.size > MAX_ENTRIES

      zip.each do |entry|
        next if entry.directory?
        next unless entry.name == kind[:data] || asset_name?(format, entry.name)

        read = read_entry(entry, kind)
        unpacked += read.bytesize
        raise Refusal, "That file unpacks to more than #{kind[:max_bytes] / 1.megabyte} MB, too much for #{kind[:what]}." if unpacked > kind[:max_bytes]

        if entry.name == kind[:data]
          data = JSON.parse(read)
        else
          assets[entry.name] = Asset.new(name: entry.name, bytes: read)
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

  # An entry's bytes, read no further than an entry may be: what the zip
  # says an entry's size is can lie, so it's what comes out that counts.
  def self.read_entry(entry, kind)
    raise Refusal, "#{entry.name} in that file is too big." if entry.size > kind[:entry_bytes]

    read = entry.get_input_stream.read(kind[:entry_bytes] + 1).to_s
    raise Refusal, "#{entry.name} in that file is too big." if read.bytesize > kind[:entry_bytes]

    read
  end
  private_class_method :read_entry

  # A file from the archive into an attachment slot, when it's the kind the
  # slot takes ("image", "audio"). A name the archive doesn't have is
  # skipped: the slot stays empty, as in a package without art.
  def attach(slot, name, kind: "image")
    asset = name.is_a?(String) && assets[name]
    return unless asset && CONTENT_TYPES.fetch(kind).include?(asset.content_type)

    slot.attach(io: StringIO.new(asset.bytes), filename: File.basename(asset.name), content_type: asset.content_type)
  end
end
