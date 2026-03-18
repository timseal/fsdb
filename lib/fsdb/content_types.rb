# frozen_string_literal: true

module Fsdb
  module ContentTypes
    EXTENSION_MAP = {
      # Video
      %w[mp4 mkv avi mov wmv flv webm m4v mpg mpeg ts vob] => "video",
      # Audio
      %w[mp3 flac aac ogg wav m4a opus wma aiff ape alac] => "audio",
      # Image
      %w[jpg jpeg png gif webp svg tiff bmp heic heif raw cr2 nef arw dng] => "image",
      # Ebook
      %w[epub mobi azw azw3 djvu fb2 lit lrf] => "ebook",
      # Document
      %w[pdf doc docx odt txt rtf md rst tex ppt pptx xls xlsx pages numbers keynote] => "document",
      # Code
      %w[rb py js ts go rs c cpp h hpp java sh bash zsh fish
         sql html htm css scss sass yaml yml toml json xml
         swift kt scala lua r php cs ex exs clj hs vim] => "code",
      # Archive
      %w[zip tar gz bz2 xz zst 7z rar dmg iso tgz tbz2 cab] => "archive",
      # Data
      %w[csv tsv parquet sqlite sqlite3 db npy npz hdf5 h5 jsonl] => "data",
      # Font
      %w[ttf otf woff woff2 eot] => "font",
    }.each_with_object({}) { |(exts, type), h| exts.each { |e| h[e] = type } }.freeze

    ALL_TYPES = EXTENSION_MAP.values.uniq.sort.freeze

    def self.detect(path)
      ext = File.extname(path.to_s).delete_prefix(".").downcase
      EXTENSION_MAP[ext]
    end
  end
end
