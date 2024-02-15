# frozen_string_literal: true

module WahWah
  class OggTag < Tag
    extend TagDelegate

    tag_delegate :@tag,
      :title,
      :album,
      :albumartist,
      :track,
      :artist,
      :year,
      :genre,
      :disc,
      :composer,
      :sample_rate,
      :lyrics

    # Since OggTag uses lazy loading, it needs the file to stay open for when
    # lazy-loaded attributes are accessed. Thus, we must avoid Tag::initialize
    # closing the file for us.
    def initialize(file)
      # `Pathname`s respond to :read, but we still want to open them.
      @opened = if file.respond_to?(:read) && !file.respond_to?(:open)
        false
      else
        file = File.open(file, "rb")
        true
      end

      super(file)
    end

    # Oggs require reading to the end of the file in order to calculate their
    # duration (as it's not stored in any header or metadata). Thus, if the
    # file-like object supplied to WahWah is a streaming download, getting the
    # duration would download the entire audio file, which may not be
    # desirable. Making it lazy in this manner allows the user to avoid that.
    def duration
      return @duration if @duration
      @duration = parse_duration
      # Only `duration` uses the file (`bitrate` uses `duration`).
      @file_io.close if @opened
      return @duration
    end

    # Requires duration to calculate, so lazy as well.
    def bitrate
      return @bitrate if @bitrate
      @bitrate = parse_bitrate
      return @bitrate
    end

    def load_fully
      super
      duration
      bitrate
    end

    private

    def packets
      @packets ||= Ogg::Packets.new(@file_io)
    end

    def pages
      @pages ||= Ogg::Pages.new(@file_io)
    end

    def parse
      identification_packet, comment_packet = packets.first(2)
      return if identification_packet.nil? || comment_packet.nil?

      @overhead_packets_size = identification_packet.size + comment_packet.size
      
      @tag = if identification_packet.start_with?("\x01vorbis")
        Ogg::VorbisTag.new(identification_packet, comment_packet)
      elsif identification_packet.start_with?("OpusHead")
        Ogg::OpusTag.new(identification_packet, comment_packet)
      elsif identification_packet.start_with?("\x7FFLAC")
        Ogg::FlacTag.new(identification_packet, comment_packet)
      end

      @bit_depth = parse_bit_depth
    end

    def parse_duration
      return @tag.duration if @tag.respond_to? :duration

      last_page = pages.to_a.last
      pre_skip = @tag.respond_to?(:pre_skip) ? @tag.pre_skip : 0

      (last_page.granule_position - pre_skip) / @tag.sample_rate.to_f
    end

    def parse_bitrate
      return @tag.bitrate if @tag.respond_to? :bitrate
      ((file_size - @overhead_packets_size) * 8.0 / duration / 1000).round
    end

    def parse_bit_depth
      @tag.bit_depth if @tag.respond_to? :bit_depth
    end
  end
end
