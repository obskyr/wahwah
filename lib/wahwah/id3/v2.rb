# frozen_string_literal: true

module WahWah
  module ID3
    class V2 < Tag
      TAG_ID = 'ID3'
      HEADER_SIZE = 10
      HEADER_FORMAT = "A3CC#{'B8' * 5}"

      attr_reader :major_version, :tag_flags, :tag_size

      def parse
        parse_header
        parse_body
      end

      # The second bit in flags byte indicates whether or not the header
      # is followed by an extended header.
      def has_extended_header?
        tag_flags[1] == '1'
      end

      private

        # The ID3v2 tag header, which should be the first information in the file,
        # is 10 bytes as follows:

        # ID3v2/file identifier   "ID3"
        # ID3v2 version           $03 00
        # ID3v2 flags             %abc00000
        # ID3v2 size              4 * %0xxxxxxx
        def parse_header
          @file_io.rewind
          header = @file_io.read(HEADER_SIZE).unpack(HEADER_FORMAT)

          # The first byte of ID3v2 version is it's major version,
          # while the second byte is its revision number, we don't need
          # revision number here, so ignore it.
          @major_version = header[1]
          @tag_flags = header[3]

          # Tag size is the size excluding the header size,
          # so add header size back to get total size.
          @tag_size = id3_size_caculate(header[4, 4]) + HEADER_SIZE
        end

        def parse_body
          if has_extended_header?
            # Extended header structure:
            #
            # Extended header size   $xx xx xx xx
            # Extended Flags         $xx xx
            # Size of padding        $xx xx xx xx

            # Skip extended_header
            extended_header_size = id3_size_caculate(@file_io.read(4).unpack("#{'B8' * 4}"))
            @file_io.seek(extended_header_size - 4, IO::SEEK_CUR)
          end

          loop do
            break if end_of_tag?

            frame = ID3::Frame.new(@file_io, major_version)
            next if frame.invalid?
            update_attribute(frame)
          end
        end


        def update_attribute(frame)
          name = frame.name
          value = frame.value

          case name
          when :comment
            # Because there may be more than one comment frame in each tag,
            # so push it into a array.
            @comments ||= []
            @comments.push(value)
          when :track, :disc
            # Track and disc value may be extended with a "/" character
            # and a numeric string containing the total numer.
            count, total_count = value.split('/')
            instance_variable_set("@#{name}", count.to_i)
            instance_variable_set("@#{name}_total", total_count.to_i) unless total_count.nil?
          else
            instance_variable_set("@#{name}", value)
          end
        end

        def end_of_tag?
          tag_size < @file_io.pos
        end
    end
  end
end
