# frozen_string_literal: true

module ApplicationHelper
  def humanize_bytes(bytes)
    return "0 B" if bytes.nil? || bytes.zero?

    units = %w[B KB MB GB TB]
    exp   = (Math.log(bytes) / Math.log(1024)).floor
    exp   = units.length - 1 if exp >= units.length
    format("%.1f %s", bytes.to_f / (1024**exp), units[exp])
  end

  def type_badge_class(type)
    colors = {
      "dir"      => "bg-blue-100 text-blue-800",
      "video"    => "bg-purple-100 text-purple-800",
      "audio"    => "bg-pink-100 text-pink-800",
      "image"    => "bg-green-100 text-green-800",
      "ebook"    => "bg-yellow-100 text-yellow-800",
      "document" => "bg-orange-100 text-orange-800",
      "code"     => "bg-cyan-100 text-cyan-800",
      "archive"  => "bg-gray-100 text-gray-800",
      "data"     => "bg-indigo-100 text-indigo-800",
      "font"     => "bg-teal-100 text-teal-800",
    }
    colors[type] || "bg-gray-100 text-gray-600"
  end
end
