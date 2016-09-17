# -*- encoding: utf-8 -*-

require 'hexapdf/error'
require 'hexapdf/font/cmap'
require 'hexapdf/content/parser'

module HexaPDF
  module Font
    class CMap

      # Parses CMap files.
      #
      # Currently only ToUnicode CMaps are supported.
      class Parser

        # Parses the given string and returns a CMap object.
        def parse(string)
          tokenizer = HexaPDF::Content::Tokenizer.new(string)
          cmap = CMap.new

          while (token = tokenizer.next_token) != HexaPDF::Tokenizer::NO_MORE_TOKENS
            if token.kind_of?(HexaPDF::Tokenizer::Token)
              case token
              when 'beginbfchar'.freeze then parse_bf_char(tokenizer, cmap)
              when 'beginbfrange'.freeze then parse_bf_range(tokenizer, cmap)
              when 'endcmap' then break
              end
            elsif token.kind_of?(Symbol)
              parse_dict_mapping(tokenizer, cmap, token)
            end
          end

          cmap
        rescue => e
          raise HexaPDF::Error, "Error parsing CMap: #{e.message}", e.backtrace
        end

        private

        # Parses a single mapping of a dictionary pair. The +name+ of the mapping has already been
        # parsed.
        def parse_dict_mapping(tokenizer, cmap, name)
          value = tokenizer.next_token
          return if value.kind_of?(HexaPDF::Tokenizer::Token)

          case name
          when :Registry then cmap.registry = value if value.kind_of?(String)
          when :Ordering then cmap.ordering = value if value.kind_of?(String)
          when :Supplement then cmap.supplement = value if value.kind_of?(Integer)
          when :CMapName then cmap.name = value.to_s if value.kind_of?(Symbol)
          end
        end

        # Parses the "bfchar" operator at the current position.
        def parse_bf_char(tokenizer, cmap)
          until (code = tokenizer.next_token).kind_of?(HexaPDF::Tokenizer::Token)
            str = tokenizer.next_token.encode!(::Encoding::UTF_8, ::Encoding::UTF_16BE)
            cmap.unicode_mapping[bytes_to_int(code)] = str
          end
        end

        # Parses the "bfrange" operator at the current position.
        #
        #--
        # PDF1.7 s9.10.3 and Adobe Technical Note #5411 have different views as to how "bfrange"
        # operators of the form "startCode endCode codePoint" should be handled.
        #
        # PDF1.7 mentions that the last byte of "codePoint" should be incremented, up to a maximum
        # of 255. However #5411 has the range "<1379> <137B> <90FE>" as example which contradicts
        # this.
        #
        # Additionally, #5411 mentions in section 1.4.1 that the first byte of "startCode" and
        # "endCode" have to be the same. So it seems that this is a mistake in the PDF reference.
        #++
        def parse_bf_range(tokenizer, cmap)
          until (code1 = tokenizer.next_token).kind_of?(HexaPDF::Tokenizer::Token)
            code1 = bytes_to_int(code1)
            code2 = bytes_to_int(tokenizer.next_token)
            dest = tokenizer.next_object

            if dest.kind_of?(String)
              codepoint = dest.force_encoding(::Encoding::UTF_16BE).ord
              code1.upto(code2) do |code|
                cmap.unicode_mapping[code] = '' << codepoint
                codepoint += 1
              end
            elsif dest.kind_of?(Array)
              code1.upto(code2) do |code|
                cmap.unicode_mapping[code] =
                  dest[code - code1].encode!(::Encoding::UTF_8, ::Encoding::UTF_16BE)
              end
            else
              raise HexaPDF::Error, "Invalid bfrange operator in CMap"
            end
          end
        end

        # Treats the string as an array of bytes and converts it to an integer.
        #
        # The bytes are converted in the big-endian way.
        def bytes_to_int(string)
          result = 0
          index = 0
          while index < string.length
            result = (result << 8) | string.getbyte(index)
            index += 1
          end
          result
        end

      end

    end
  end
end
