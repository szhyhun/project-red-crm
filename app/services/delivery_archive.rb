require "fileutils"
require "rubygems/package"
require "tempfile"

class DeliveryArchive
  def initialize(listing)
    @listing = listing
  end

  def build
    tempfile = Tempfile.new(["project-red-listing-#{@listing.id}-", ".tar"])
    tempfile.binmode
    Gem::Package::TarWriter.new(tempfile) do |tar|
      @listing.media_assets.ready.where(hidden: false).order(:category, :position, :created_at).each do |asset|
        source = DeliveryStorage.path_for(asset.storage_key)
        raise DeliveryStorage::MissingFile, asset.filename unless source.file?

        entry = [asset.category, File.basename(asset.filename).gsub("..", "")].join("/")
        tar.add_file_simple(entry, 0o644, source.size) do |io|
          File.open(source, "rb") { |file| IO.copy_stream(file, io) }
        end
      end
    end
    tempfile.flush
    tempfile.rewind
    tempfile
  rescue StandardError
    tempfile&.close!
    raise
  end
end
