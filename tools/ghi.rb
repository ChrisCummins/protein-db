#!/usr/bin/env ruby
# encoding: utf-8
module GHI
  module Commands
    module Version
      MAJOR   = 0
      MINOR   = 9
      PATCH   = 0
      PRE     = 20131120

      VERSION = [MAJOR, MINOR, PATCH, PRE].compact.join '.'

      def self.execute args
        puts "ghi version #{VERSION}"
      end
    end
  end
end
require 'optparse'

module GHI
  class << self
    def execute args
      STDOUT.sync = true

      double_dash = args.index { |arg| arg == '--' }
      if index = args.index { |arg| arg !~ /^-/ }
        if double_dash.nil? || index < double_dash
          command_name = args.delete_at index
          command_args = args.slice! index, args.length
        end
      end
      command_args ||= []

      option_parser = OptionParser.new do |opts|
        opts.banner = <<EOF
usage: ghi [--version] [-p|--paginate|--no-pager] [--help] <command> [<args>]
           [ -- [<user>/]<repo>]
EOF
        opts.on('--version') { command_name = 'version' }
        opts.on '-p', '--paginate', '--[no-]pager' do |paginate|
          GHI::Formatting.paginate = paginate
        end
        opts.on '--help' do
          command_args.unshift(*args)
          command_args.unshift command_name if command_name
          args.clear
          command_name = 'help'
        end
        opts.on '--[no-]color' do |colorize|
          Formatting::Colors.colorize = colorize
        end
        opts.on '-l' do
          if command_name
            raise OptionParser::InvalidOption
          else
            command_name = 'list'
          end
        end
        opts.on '-v' do
          command_name ? self.v = true : command_name = 'version'
        end
        opts.on('-V') { command_name = 'version' }
      end

      begin
        option_parser.parse! args
      rescue OptionParser::InvalidOption => e
        warn e.message.capitalize
        abort option_parser.banner
      end

      if command_name.nil?
        command_name = 'list'
      end

      if command_name == 'help'
        Commands::Help.execute command_args, option_parser.banner
      else
        command_name = fetch_alias command_name, command_args
        begin
          command = Commands.const_get command_name.capitalize
        rescue NameError
          abort "ghi: '#{command_name}' is not a ghi command. See 'ghi --help'."
        end

        # Post-command help option parsing.
        Commands::Help.execute [command_name] if command_args.first == '--help'

        begin
          command.execute command_args
        rescue OptionParser::ParseError, Commands::MissingArgument => e
          warn "#{e.message.capitalize}\n"
          abort command.new([]).options.to_s
        rescue Client::Error => e
          if e.response.is_a?(Net::HTTPNotFound) && Authorization.token.nil?
            raise Authorization::Required
          else
            abort e.message
          end
        rescue SocketError => e
          abort "Couldn't find internet."
        rescue Errno::ECONNREFUSED, Errno::ETIMEDOUT => e
          abort "Couldn't find GitHub."
        end
      end
    rescue Authorization::Required => e
      retry if Authorization.authorize!
      warn e.message
      if Authorization.token
        warn <<EOF.chomp

Not authorized for this action with your token. To regenerate a new token:
EOF
      end
      warn <<EOF

Please run 'ghi config --auth <username>'
EOF
      exit 1
    end

    def config key, options = {}
      upcase = options.fetch :upcase, true
      flags = options[:flags]
      var = key.gsub('core', 'git').gsub '.', '_'
      var.upcase! if upcase
      value = ENV[var] || `git config #{flags} #{key}`.chomp
      value unless value.empty?
    end

    attr_accessor :v
    alias v? v

    private

    ALIASES = Hash.new { |_, key|
      [key] if /^\d+$/ === key
    }.update(
      'claim'    => %w(assign),
      'create'   => %w(open),
      'e'        => %w(edit),
      'l'        => %w(list),
      'L'        => %w(label),
      'm'        => %w(comment),
      'M'        => %w(milestone),
      'new'      => %w(open),
      'o'        => %w(open),
      'reopen'   => %w(open),
      'rm'       => %w(close),
      's'        => %w(show),
      'st'       => %w(list),
      'tag'      => %w(label),
      'unassign' => %w(assign -d),
      'update'   => %w(edit)
    )

    def fetch_alias command, args
      return command unless fetched = ALIASES[command]

      # If the <command> is an issue number, check the options to see if an
      # edit or show is desired.
      if fetched.first =~ /^\d+$/
        edit_options = Commands::Edit.new([]).options.top.list
        edit_options.reject! { |arg| !arg.is_a?(OptionParser::Switch) }
        edit_options.map! { |arg| [arg.short, arg.long] }
        edit_options.flatten!
        fetched.unshift((edit_options & args).empty? ? 'show' : 'edit')
      end

      command = fetched.shift
      args.unshift(*fetched)
      command
    end
  end
end
unless defined? JSON
  require 'strscan'

  module JSON
    module Pure
      # This class implements the JSON parser that is used to parse a JSON string
      # into a Ruby data structure.
      class Parser < StringScanner
        STRING                = /" ((?:[^\x0-\x1f"\\] |
                                     # escaped special characters:
                                    \\["\\\/bfnrt] |
                                    \\u[0-9a-fA-F]{4} |
                                     # match all but escaped special characters:
                                    \\[\x20-\x21\x23-\x2e\x30-\x5b\x5d-\x61\x63-\x65\x67-\x6d\x6f-\x71\x73\x75-\xff])*)
                                "/nx
        INTEGER               = /(-?0|-?[1-9]\d*)/
        FLOAT                 = /(-?
                                  (?:0|[1-9]\d*)
                                  (?:
                                    \.\d+(?i:e[+-]?\d+) |
                                    \.\d+ |
                                    (?i:e[+-]?\d+)
                                  )
                                  )/x
        NAN                   = /NaN/
        INFINITY              = /Infinity/
        MINUS_INFINITY        = /-Infinity/
        OBJECT_OPEN           = /\{/
        OBJECT_CLOSE          = /\}/
        ARRAY_OPEN            = /\[/
        ARRAY_CLOSE           = /\]/
        PAIR_DELIMITER        = /:/
        COLLECTION_DELIMITER  = /,/
        TRUE                  = /true/
        FALSE                 = /false/
        NULL                  = /null/
        IGNORE                = %r(
          (?:
           //[^\n\r]*[\n\r]| # line comments
           /\*               # c-style comments
           (?:
            [^*/]|        # normal chars
            /[^*]|        # slashes that do not start a nested comment
            \*[^/]|       # asterisks that do not end this comment
            /(?=\*/)      # single slash before this comment's end
           )*
             \*/               # the End of this comment
             |[ \t\r\n]+       # whitespaces: space, horicontal tab, lf, cr
          )+
        )mx

        UNPARSED = Object.new

        # Creates a new JSON::Pure::Parser instance for the string _source_.
        #
        # It will be configured by the _opts_ hash. _opts_ can have the following
        # keys:
        # * *max_nesting*: The maximum depth of nesting allowed in the parsed data
        #   structures. Disable depth checking with :max_nesting => false|nil|0,
        #   it defaults to 19.
        # * *allow_nan*: If set to true, allow NaN, Infinity and -Infinity in
        #   defiance of RFC 4627 to be parsed by the Parser. This option defaults
        #   to false.
        # * *symbolize_names*: If set to true, returns symbols for the names
        #   (keys) in a JSON object. Otherwise strings are returned, which is also
        #   the default.
        # * *create_additions*: If set to false, the Parser doesn't create
        #   additions even if a matchin class and create_id was found. This option
        #   defaults to true.
        # * *object_class*: Defaults to Hash
        # * *array_class*: Defaults to Array
        # * *quirks_mode*: Enables quirks_mode for parser, that is for example
        #   parsing single JSON values instead of documents is possible.
        def initialize(source, opts = {})
          opts ||= {}
          unless @quirks_mode = opts[:quirks_mode]
            source = convert_encoding source
          end
          super source
          if !opts.key?(:max_nesting) # defaults to 19
            @max_nesting = 19
          elsif opts[:max_nesting]
            @max_nesting = opts[:max_nesting]
          else
            @max_nesting = 0
          end
          @allow_nan = !!opts[:allow_nan]
          @symbolize_names = !!opts[:symbolize_names]
          if opts.key?(:create_additions)
            @create_additions = !!opts[:create_additions]
          else
            @create_additions = true
          end
          @create_id = @create_additions ? JSON.create_id : nil
          @object_class = opts[:object_class] || Hash
          @array_class  = opts[:array_class] || Array
          @match_string = opts[:match_string]
        end

        alias source string

        def quirks_mode?
          !!@quirks_mode
        end

        def reset
          super
          @current_nesting = 0
        end

        # Parses the current JSON string _source_ and returns the complete data
        # structure as a result.
        def parse
          reset
          obj = nil
          if @quirks_mode
            while !eos? && skip(IGNORE)
            end
            if eos?
              raise ParserError, "source did not contain any JSON!"
            else
              obj = parse_value
              obj == UNPARSED and raise ParserError, "source did not contain any JSON!"
            end
          else
            until eos?
              case
              when scan(OBJECT_OPEN)
                obj and raise ParserError, "source '#{peek(20)}' not in JSON!"
                @current_nesting = 1
                obj = parse_object
              when scan(ARRAY_OPEN)
                obj and raise ParserError, "source '#{peek(20)}' not in JSON!"
                @current_nesting = 1
                obj = parse_array
              when skip(IGNORE)
                ;
              else
                raise ParserError, "source '#{peek(20)}' not in JSON!"
              end
            end
            obj or raise ParserError, "source did not contain any JSON!"
          end
          obj
        end

        private

        def convert_encoding(source)
          if source.respond_to?(:to_str)
            source = source.to_str
          else
            raise TypeError, "#{source.inspect} is not like a string"
          end
          if defined?(::Encoding)
            if source.encoding == ::Encoding::ASCII_8BIT
              b = source[0, 4].bytes.to_a
              source =
                case
                when b.size >= 4 && b[0] == 0 && b[1] == 0 && b[2] == 0
                  source.dup.force_encoding(::Encoding::UTF_32BE).encode!(::Encoding::UTF_8)
                when b.size >= 4 && b[0] == 0 && b[2] == 0
                  source.dup.force_encoding(::Encoding::UTF_16BE).encode!(::Encoding::UTF_8)
                when b.size >= 4 && b[1] == 0 && b[2] == 0 && b[3] == 0
                  source.dup.force_encoding(::Encoding::UTF_32LE).encode!(::Encoding::UTF_8)
                when b.size >= 4 && b[1] == 0 && b[3] == 0
                  source.dup.force_encoding(::Encoding::UTF_16LE).encode!(::Encoding::UTF_8)
                else
                  source.dup
                end
            else
              source = source.encode(::Encoding::UTF_8)
            end
            source.force_encoding(::Encoding::ASCII_8BIT)
          else
            b = source
            source =
              case
              when b.size >= 4 && b[0] == 0 && b[1] == 0 && b[2] == 0
                JSON.iconv('utf-8', 'utf-32be', b)
              when b.size >= 4 && b[0] == 0 && b[2] == 0
                JSON.iconv('utf-8', 'utf-16be', b)
              when b.size >= 4 && b[1] == 0 && b[2] == 0 && b[3] == 0
                JSON.iconv('utf-8', 'utf-32le', b)
              when b.size >= 4 && b[1] == 0 && b[3] == 0
                JSON.iconv('utf-8', 'utf-16le', b)
              else
                b
              end
          end
          source
        end

        # Unescape characters in strings.
        UNESCAPE_MAP = Hash.new { |h, k| h[k] = k.chr }
        UNESCAPE_MAP.update({
          ?"  => '"',
          ?\\ => '\\',
          ?/  => '/',
          ?b  => "\b",
          ?f  => "\f",
          ?n  => "\n",
          ?r  => "\r",
          ?t  => "\t",
          ?u  => nil,
        })

        EMPTY_8BIT_STRING = ''
        if ::String.method_defined?(:encode)
          EMPTY_8BIT_STRING.force_encoding Encoding::ASCII_8BIT
        end

        def parse_string
          if scan(STRING)
            return '' if self[1].empty?
            string = self[1].gsub(%r((?:\\[\\bfnrt"/]|(?:\\u(?:[A-Fa-f\d]{4}))+|\\[\x20-\xff]))n) do |c|
              if u = UNESCAPE_MAP[$&[1]]
                u
              else # \uXXXX
                bytes = EMPTY_8BIT_STRING.dup
                i = 0
                while c[6 * i] == ?\\ && c[6 * i + 1] == ?u
                  bytes << c[6 * i + 2, 2].to_i(16) << c[6 * i + 4, 2].to_i(16)
                  i += 1
                end
                JSON.iconv('utf-8', 'utf-16be', bytes)
              end
            end
            if string.respond_to?(:force_encoding)
              string.force_encoding(::Encoding::UTF_8)
            end
            if @create_additions and @match_string
              for (regexp, klass) in @match_string
                klass.json_creatable? or next
                string =~ regexp and return klass.json_create(string)
              end
            end
            string
          else
            UNPARSED
          end
        rescue => e
          raise ParserError, "Caught #{e.class} at '#{peek(20)}': #{e}"
        end

        def parse_value
          case
          when scan(FLOAT)
            Float(self[1])
          when scan(INTEGER)
            Integer(self[1])
          when scan(TRUE)
            true
          when scan(FALSE)
            false
          when scan(NULL)
            nil
          when (string = parse_string) != UNPARSED
            string
          when scan(ARRAY_OPEN)
            @current_nesting += 1
            ary = parse_array
            @current_nesting -= 1
            ary
          when scan(OBJECT_OPEN)
            @current_nesting += 1
            obj = parse_object
            @current_nesting -= 1
            obj
          when @allow_nan && scan(NAN)
            NaN
          when @allow_nan && scan(INFINITY)
            Infinity
          when @allow_nan && scan(MINUS_INFINITY)
            MinusInfinity
          else
            UNPARSED
          end
        end

        def parse_array
          raise NestingError, "nesting of #@current_nesting is too deep" if
            @max_nesting.nonzero? && @current_nesting > @max_nesting
          result = @array_class.new
          delim = false
          until eos?
            case
            when (value = parse_value) != UNPARSED
              delim = false
              result << value
              skip(IGNORE)
              if scan(COLLECTION_DELIMITER)
                delim = true
              elsif match?(ARRAY_CLOSE)
                ;
              else
                raise ParserError, "expected ',' or ']' in array at '#{peek(20)}'!"
              end
            when scan(ARRAY_CLOSE)
              if delim
                raise ParserError, "expected next element in array at '#{peek(20)}'!"
              end
              break
            when skip(IGNORE)
              ;
            else
              raise ParserError, "unexpected token in array at '#{peek(20)}'!"
            end
          end
          result
        end

        def parse_object
          raise NestingError, "nesting of #@current_nesting is too deep" if
            @max_nesting.nonzero? && @current_nesting > @max_nesting
          result = @object_class.new
          delim = false
          until eos?
            case
            when (string = parse_string) != UNPARSED
              skip(IGNORE)
              unless scan(PAIR_DELIMITER)
                raise ParserError, "expected ':' in object at '#{peek(20)}'!"
              end
              skip(IGNORE)
              unless (value = parse_value).equal? UNPARSED
                result[@symbolize_names ? string.to_sym : string] = value
                delim = false
                skip(IGNORE)
                if scan(COLLECTION_DELIMITER)
                  delim = true
                elsif match?(OBJECT_CLOSE)
                  ;
                else
                  raise ParserError, "expected ',' or '}' in object at '#{peek(20)}'!"
                end
              else
                raise ParserError, "expected value in object at '#{peek(20)}'!"
              end
            when scan(OBJECT_CLOSE)
              if delim
                raise ParserError, "expected next name, value pair in object at '#{peek(20)}'!"
              end
              if @create_additions and klassname = result[@create_id]
                klass = JSON.deep_const_get klassname
                break unless klass and klass.json_creatable?
                result = klass.json_create(result)
              end
              break
            when skip(IGNORE)
              ;
            else
              raise ParserError, "unexpected token in object at '#{peek(20)}'!"
            end
          end
          result
        end
      end
    end
  end

  module JSON
    MAP = {
      "\x0" => '\u0000',
      "\x1" => '\u0001',
      "\x2" => '\u0002',
      "\x3" => '\u0003',
      "\x4" => '\u0004',
      "\x5" => '\u0005',
      "\x6" => '\u0006',
      "\x7" => '\u0007',
      "\b"  =>  '\b',
      "\t"  =>  '\t',
      "\n"  =>  '\n',
      "\xb" => '\u000b',
      "\f"  =>  '\f',
      "\r"  =>  '\r',
      "\xe" => '\u000e',
      "\xf" => '\u000f',
      "\x10" => '\u0010',
      "\x11" => '\u0011',
      "\x12" => '\u0012',
      "\x13" => '\u0013',
      "\x14" => '\u0014',
      "\x15" => '\u0015',
      "\x16" => '\u0016',
      "\x17" => '\u0017',
      "\x18" => '\u0018',
      "\x19" => '\u0019',
      "\x1a" => '\u001a',
      "\x1b" => '\u001b',
      "\x1c" => '\u001c',
      "\x1d" => '\u001d',
      "\x1e" => '\u001e',
      "\x1f" => '\u001f',
      '"'   =>  '\"',
      '\\'  =>  '\\\\',
    } # :nodoc:

    # Convert a UTF8 encoded Ruby string _string_ to a JSON string, encoded with
    # UTF16 big endian characters as \u????, and return it.
    if defined?(::Encoding)
      def utf8_to_json(string) # :nodoc:
        string = string.dup
        string << '' # XXX workaround: avoid buffer sharing
        string.force_encoding(::Encoding::ASCII_8BIT)
        string.gsub!(/["\\\x0-\x1f]/) { MAP[$&] }
        string.force_encoding(::Encoding::UTF_8)
        string
      end

      def utf8_to_json_ascii(string) # :nodoc:
        string = string.dup
        string << '' # XXX workaround: avoid buffer sharing
        string.force_encoding(::Encoding::ASCII_8BIT)
        string.gsub!(/["\\\x0-\x1f]/) { MAP[$&] }
        string.gsub!(/(
                        (?:
                          [\xc2-\xdf][\x80-\xbf]    |
                          [\xe0-\xef][\x80-\xbf]{2} |
                          [\xf0-\xf4][\x80-\xbf]{3}
                        )+ |
                        [\x80-\xc1\xf5-\xff]       # invalid
                      )/nx) { |c|
                        c.size == 1 and raise GeneratorError, "invalid utf8 byte: '#{c}'"
                        s = JSON.iconv('utf-16be', 'utf-8', c).unpack('H*')[0]
                        s.gsub!(/.{4}/n, '\\\\u\&')
                      }
        string.force_encoding(::Encoding::UTF_8)
        string
      rescue => e
        raise GeneratorError, "Caught #{e.class}: #{e}"
      end
    else
      def utf8_to_json(string) # :nodoc:
        string.gsub(/["\\\x0-\x1f]/) { MAP[$&] }
      end

      def utf8_to_json_ascii(string) # :nodoc:
        string = string.gsub(/["\\\x0-\x1f]/) { MAP[$&] }
        string.gsub!(/(
                        (?:
                          [\xc2-\xdf][\x80-\xbf]    |
                          [\xe0-\xef][\x80-\xbf]{2} |
                          [\xf0-\xf4][\x80-\xbf]{3}
                        )+ |
                        [\x80-\xc1\xf5-\xff]       # invalid
                      )/nx) { |c|
          c.size == 1 and raise GeneratorError, "invalid utf8 byte: '#{c}'"
          s = JSON.iconv('utf-16be', 'utf-8', c).unpack('H*')[0]
          s.gsub!(/.{4}/n, '\\\\u\&')
        }
        string
      rescue => e
        raise GeneratorError, "Caught #{e.class}: #{e}"
      end
    end
    module_function :utf8_to_json, :utf8_to_json_ascii

    module Pure
      module Generator
        # This class is used to create State instances, that are use to hold data
        # while generating a JSON text from a Ruby data structure.
        class State
          # Creates a State object from _opts_, which ought to be Hash to create
          # a new State instance configured by _opts_, something else to create
          # an unconfigured instance. If _opts_ is a State object, it is just
          # returned.
          def self.from_state(opts)
            case
            when self === opts
              opts
            when opts.respond_to?(:to_hash)
              new(opts.to_hash)
            when opts.respond_to?(:to_h)
              new(opts.to_h)
            else
              SAFE_STATE_PROTOTYPE.dup
            end
          end

          # Instantiates a new State object, configured by _opts_.
          #
          # _opts_ can have the following keys:
          #
          # * *indent*: a string used to indent levels (default: ''),
          # * *space*: a string that is put after, a : or , delimiter (default: ''),
          # * *space_before*: a string that is put before a : pair delimiter (default: ''),
          # * *object_nl*: a string that is put at the end of a JSON object (default: ''),
          # * *array_nl*: a string that is put at the end of a JSON array (default: ''),
          # * *check_circular*: is deprecated now, use the :max_nesting option instead,
          # * *max_nesting*: sets the maximum level of data structure nesting in
          #   the generated JSON, max_nesting = 0 if no maximum should be checked.
          # * *allow_nan*: true if NaN, Infinity, and -Infinity should be
          #   generated, otherwise an exception is thrown, if these values are
          #   encountered. This options defaults to false.
          # * *quirks_mode*: Enables quirks_mode for parser, that is for example
          #   generating single JSON values instead of documents is possible.
          def initialize(opts = {})
            @indent                = ''
            @space                 = ''
            @space_before          = ''
            @object_nl             = ''
            @array_nl              = ''
            @allow_nan             = false
            @ascii_only            = false
            @quirks_mode           = false
            @buffer_initial_length = 1024
            configure opts
          end

          # This string is used to indent levels in the JSON text.
          attr_accessor :indent

          # This string is used to insert a space between the tokens in a JSON
          # string.
          attr_accessor :space

          # This string is used to insert a space before the ':' in JSON objects.
          attr_accessor :space_before

          # This string is put at the end of a line that holds a JSON object (or
          # Hash).
          attr_accessor :object_nl

          # This string is put at the end of a line that holds a JSON array.
          attr_accessor :array_nl

          # This integer returns the maximum level of data structure nesting in
          # the generated JSON, max_nesting = 0 if no maximum is checked.
          attr_accessor :max_nesting

          # If this attribute is set to true, quirks mode is enabled, otherwise
          # it's disabled.
          attr_accessor :quirks_mode

          # :stopdoc:
          attr_reader :buffer_initial_length

          def buffer_initial_length=(length)
            if length > 0
              @buffer_initial_length = length
            end
          end
          # :startdoc:

          # This integer returns the current depth data structure nesting in the
          # generated JSON.
          attr_accessor :depth

          def check_max_nesting # :nodoc:
            return if @max_nesting.zero?
            current_nesting = depth + 1
            current_nesting > @max_nesting and
              raise NestingError, "nesting of #{current_nesting} is too deep"
          end

          # Returns true, if circular data structures are checked,
          # otherwise returns false.
          def check_circular?
            !@max_nesting.zero?
          end

          # Returns true if NaN, Infinity, and -Infinity should be considered as
          # valid JSON and output.
          def allow_nan?
            @allow_nan
          end

          # Returns true, if only ASCII characters should be generated. Otherwise
          # returns false.
          def ascii_only?
            @ascii_only
          end

          # Returns true, if quirks mode is enabled. Otherwise returns false.
          def quirks_mode?
            @quirks_mode
          end

          # Configure this State instance with the Hash _opts_, and return
          # itself.
          def configure(opts)
            @indent         = opts[:indent] if opts.key?(:indent)
            @space          = opts[:space] if opts.key?(:space)
            @space_before   = opts[:space_before] if opts.key?(:space_before)
            @object_nl      = opts[:object_nl] if opts.key?(:object_nl)
            @array_nl       = opts[:array_nl] if opts.key?(:array_nl)
            @allow_nan      = !!opts[:allow_nan] if opts.key?(:allow_nan)
            @ascii_only     = opts[:ascii_only] if opts.key?(:ascii_only)
            @depth          = opts[:depth] || 0
            @quirks_mode    = opts[:quirks_mode] if opts.key?(:quirks_mode)
            if !opts.key?(:max_nesting) # defaults to 19
              @max_nesting = 19
            elsif opts[:max_nesting]
              @max_nesting = opts[:max_nesting]
            else
              @max_nesting = 0
            end
            self
          end
          alias merge configure

          # Returns the configuration instance variables as a hash, that can be
          # passed to the configure method.
          def to_h
            result = {}
            for iv in %w[indent space space_before object_nl array_nl allow_nan max_nesting ascii_only quirks_mode buffer_initial_length depth]
              result[iv.intern] = instance_variable_get("@#{iv}")
            end
            result
          end

          # Generates a valid JSON document from object +obj+ and returns the
          # result. If no valid JSON document can be created this method raises a
          # GeneratorError exception.
          def generate(obj)
            result = obj.to_json(self)
            unless @quirks_mode
              unless result =~ /\A\s*\[/ && result =~ /\]\s*\Z/ ||
                result =~ /\A\s*\{/ && result =~ /\}\s*\Z/
              then
                raise GeneratorError, "only generation of JSON objects or arrays allowed"
              end
            end
            result
          end

          # Return the value returned by method +name+.
          def [](name)
            __send__ name
          end
        end

        module GeneratorMethods
          module Object
            # Converts this object to a string (calling #to_s), converts
            # it to a JSON string, and returns the result. This is a fallback, if no
            # special method #to_json was defined for some object.
            def to_json(*) to_s.to_json end
          end

          module Hash
            # Returns a JSON string containing a JSON object, that is unparsed from
            # this Hash instance.
            # _state_ is a JSON::State object, that can also be used to configure the
            # produced JSON string output further.
            # _depth_ is used to find out nesting depth, to indent accordingly.
            def to_json(state = nil, *)
              state = State.from_state(state)
              state.check_max_nesting
              json_transform(state)
            end

            private

            def json_shift(state)
              state.object_nl.empty? or return ''
              state.indent * state.depth
            end

            def json_transform(state)
              delim = ','
              delim << state.object_nl
              result = '{'
              result << state.object_nl
              depth = state.depth += 1
              first = true
              indent = !state.object_nl.empty?
              each { |key,value|
                result << delim unless first
                result << state.indent * depth if indent
                result << key.to_s.to_json(state)
                result << state.space_before
                result << ':'
                result << state.space
                result << value.to_json(state)
                first = false
              }
              depth = state.depth -= 1
              result << state.object_nl
              result << state.indent * depth if indent if indent
              result << '}'
              result
            end
          end

          module Array
            # Returns a JSON string containing a JSON array, that is unparsed from
            # this Array instance.
            # _state_ is a JSON::State object, that can also be used to configure the
            # produced JSON string output further.
            def to_json(state = nil, *)
              state = State.from_state(state)
              state.check_max_nesting
              json_transform(state)
            end

            private

            def json_transform(state)
              delim = ','
              delim << state.array_nl
              result = '['
              result << state.array_nl
              depth = state.depth += 1
              first = true
              indent = !state.array_nl.empty?
              each { |value|
                result << delim unless first
                result << state.indent * depth if indent
                result << value.to_json(state)
                first = false
              }
              depth = state.depth -= 1
              result << state.array_nl
              result << state.indent * depth if indent
              result << ']'
            end
          end

          module Integer
            # Returns a JSON string representation for this Integer number.
            def to_json(*) to_s end
          end

          module Float
            # Returns a JSON string representation for this Float number.
            def to_json(state = nil, *)
              state = State.from_state(state)
              case
              when infinite?
                if state.allow_nan?
                  to_s
                else
                  raise GeneratorError, "#{self} not allowed in JSON"
                end
              when nan?
                if state.allow_nan?
                  to_s
                else
                  raise GeneratorError, "#{self} not allowed in JSON"
                end
              else
                to_s
              end
            end
          end

          module String
            if defined?(::Encoding)
              # This string should be encoded with UTF-8 A call to this method
              # returns a JSON string encoded with UTF16 big endian characters as
              # \u????.
              def to_json(state = nil, *args)
                state = State.from_state(state)
                if encoding == ::Encoding::UTF_8
                  string = self
                else
                  string = encode(::Encoding::UTF_8)
                end
                if state.ascii_only?
                  '"' << JSON.utf8_to_json_ascii(string) << '"'
                else
                  '"' << JSON.utf8_to_json(string) << '"'
                end
              end
            else
              # This string should be encoded with UTF-8 A call to this method
              # returns a JSON string encoded with UTF16 big endian characters as
              # \u????.
              def to_json(state = nil, *args)
                state = State.from_state(state)
                if state.ascii_only?
                  '"' << JSON.utf8_to_json_ascii(self) << '"'
                else
                  '"' << JSON.utf8_to_json(self) << '"'
                end
              end
            end

            # Module that holds the extinding methods if, the String module is
            # included.
            module Extend
              # Raw Strings are JSON Objects (the raw bytes are stored in an
              # array for the key "raw"). The Ruby String can be created by this
              # module method.
              def json_create(o)
                o['raw'].pack('C*')
              end
            end

            # Extends _modul_ with the String::Extend module.
            def self.included(modul)
              modul.extend Extend
            end

            # This method creates a raw object hash, that can be nested into
            # other data structures and will be unparsed as a raw string. This
            # method should be used, if you want to convert raw strings to JSON
            # instead of UTF-8 strings, e. g. binary data.
            def to_json_raw_object
              {
                JSON.create_id  => self.class.name,
                'raw'           => self.unpack('C*'),
              }
            end

            # This method creates a JSON text from the result of
            # a call to to_json_raw_object of this String.
            def to_json_raw(*args)
              to_json_raw_object.to_json(*args)
            end
          end

          module TrueClass
            # Returns a JSON string for true: 'true'.
            def to_json(*) 'true' end
          end

          module FalseClass
            # Returns a JSON string for false: 'false'.
            def to_json(*) 'false' end
          end

          module NilClass
            # Returns a JSON string for nil: 'null'.
            def to_json(*) 'null' end
          end
        end
      end
    end
  end

  module JSON
    class << self
      # If _object_ is string-like, parse the string and return the parsed result
      # as a Ruby data structure. Otherwise generate a JSON text from the Ruby
      # data structure object and return it.
      #
      # The _opts_ argument is passed through to generate/parse respectively. See
      # generate and parse for their documentation.
      def [](object, opts = {})
        if object.respond_to? :to_str
          JSON.parse(object.to_str, opts)
        else
          JSON.generate(object, opts)
        end
      end

      # Returns the JSON parser class that is used by JSON. This is either
      # JSON::Ext::Parser or JSON::Pure::Parser.
      attr_reader :parser

      # Set the JSON parser class _parser_ to be used by JSON.
      def parser=(parser) # :nodoc:
        @parser = parser
        remove_const :Parser if JSON.const_defined_in?(self, :Parser)
        const_set :Parser, parser
      end

      # Return the constant located at _path_. The format of _path_ has to be
      # either ::A::B::C or A::B::C. In any case, A has to be located at the top
      # level (absolute namespace path?). If there doesn't exist a constant at
      # the given path, an ArgumentError is raised.
      def deep_const_get(path) # :nodoc:
        path.to_s.split(/::/).inject(Object) do |p, c|
          case
          when c.empty?                     then p
          when JSON.const_defined_in?(p, c) then p.const_get(c)
          else
            begin
              p.const_missing(c)
            rescue NameError => e
              raise ArgumentError, "can't get const #{path}: #{e}"
            end
          end
        end
      end

      # Set the module _generator_ to be used by JSON.
      def generator=(generator) # :nodoc:
        old, $VERBOSE = $VERBOSE, nil
        @generator = generator
        generator_methods = generator::GeneratorMethods
        for const in generator_methods.constants
          klass = deep_const_get(const)
          modul = generator_methods.const_get(const)
          klass.class_eval do
            instance_methods(false).each do |m|
              m.to_s == 'to_json' and remove_method m
            end
            include modul
          end
        end
        self.state = generator::State
        const_set :State, self.state
        const_set :SAFE_STATE_PROTOTYPE, State.new
        const_set :FAST_STATE_PROTOTYPE, State.new(
          :indent         => '',
          :space          => '',
          :object_nl      => "",
          :array_nl       => "",
          :max_nesting    => false
        )
        const_set :PRETTY_STATE_PROTOTYPE, State.new(
          :indent         => '  ',
          :space          => ' ',
          :object_nl      => "\n",
          :array_nl       => "\n"
        )
      ensure
        $VERBOSE = old
      end

      # Returns the JSON generator module that is used by JSON. This is
      # either JSON::Ext::Generator or JSON::Pure::Generator.
      attr_reader :generator

      # Returns the JSON generator state class that is used by JSON. This is
      # either JSON::Ext::Generator::State or JSON::Pure::Generator::State.
      attr_accessor :state

      # This is create identifier, which is used to decide if the _json_create_
      # hook of a class should be called. It defaults to 'json_class'.
      attr_accessor :create_id
    end
    self.create_id = 'json_class'

    NaN           = 0.0/0

    Infinity      = 1.0/0

    MinusInfinity = -Infinity

    # The base exception for JSON errors.
    class JSONError < StandardError; end

    # This exception is raised if a parser error occurs.
    class ParserError < JSONError; end

    # This exception is raised if the nesting of parsed data structures is too
    # deep.
    class NestingError < ParserError; end

    # :stopdoc:
    class CircularDatastructure < NestingError; end
    # :startdoc:

    # This exception is raised if a generator or unparser error occurs.
    class GeneratorError < JSONError; end
    # For backwards compatibility
    UnparserError = GeneratorError

    # This exception is raised if the required unicode support is missing on the
    # system. Usually this means that the iconv library is not installed.
    class MissingUnicodeSupport < JSONError; end

    module_function

    # Parse the JSON document _source_ into a Ruby data structure and return it.
    #
    # _opts_ can have the following
    # keys:
    # * *max_nesting*: The maximum depth of nesting allowed in the parsed data
    #   structures. Disable depth checking with :max_nesting => false. It defaults
    #   to 19.
    # * *allow_nan*: If set to true, allow NaN, Infinity and -Infinity in
    #   defiance of RFC 4627 to be parsed by the Parser. This option defaults
    #   to false.
    # * *symbolize_names*: If set to true, returns symbols for the names
    #   (keys) in a JSON object. Otherwise strings are returned. Strings are
    #   the default.
    # * *create_additions*: If set to false, the Parser doesn't create
    #   additions even if a matching class and create_id was found. This option
    #   defaults to true.
    # * *object_class*: Defaults to Hash
    # * *array_class*: Defaults to Array
    def parse(source, opts = {})
      Parser.new(source, opts).parse
    end

    # Parse the JSON document _source_ into a Ruby data structure and return it.
    # The bang version of the parse method defaults to the more dangerous values
    # for the _opts_ hash, so be sure only to parse trusted _source_ documents.
    #
    # _opts_ can have the following keys:
    # * *max_nesting*: The maximum depth of nesting allowed in the parsed data
    #   structures. Enable depth checking with :max_nesting => anInteger. The parse!
    #   methods defaults to not doing max depth checking: This can be dangerous
    #   if someone wants to fill up your stack.
    # * *allow_nan*: If set to true, allow NaN, Infinity, and -Infinity in
    #   defiance of RFC 4627 to be parsed by the Parser. This option defaults
    #   to true.
    # * *create_additions*: If set to false, the Parser doesn't create
    #   additions even if a matching class and create_id was found. This option
    #   defaults to true.
    def parse!(source, opts = {})
      opts = {
        :max_nesting  => false,
        :allow_nan    => true
      }.update(opts)
      Parser.new(source, opts).parse
    end

    # Generate a JSON document from the Ruby data structure _obj_ and return
    # it. _state_ is * a JSON::State object,
    # * or a Hash like object (responding to to_hash),
    # * an object convertible into a hash by a to_h method,
    # that is used as or to configure a State object.
    #
    # It defaults to a state object, that creates the shortest possible JSON text
    # in one line, checks for circular data structures and doesn't allow NaN,
    # Infinity, and -Infinity.
    #
    # A _state_ hash can have the following keys:
    # * *indent*: a string used to indent levels (default: ''),
    # * *space*: a string that is put after, a : or , delimiter (default: ''),
    # * *space_before*: a string that is put before a : pair delimiter (default: ''),
    # * *object_nl*: a string that is put at the end of a JSON object (default: ''),
    # * *array_nl*: a string that is put at the end of a JSON array (default: ''),
    # * *allow_nan*: true if NaN, Infinity, and -Infinity should be
    #   generated, otherwise an exception is thrown if these values are
    #   encountered. This options defaults to false.
    # * *max_nesting*: The maximum depth of nesting allowed in the data
    #   structures from which JSON is to be generated. Disable depth checking
    #   with :max_nesting => false, it defaults to 19.
    #
    # See also the fast_generate for the fastest creation method with the least
    # amount of sanity checks, and the pretty_generate method for some
    # defaults for pretty output.
    def generate(obj, opts = nil)
      if State === opts
        state, opts = opts, nil
      else
        state = SAFE_STATE_PROTOTYPE.dup
      end
      if opts
        if opts.respond_to? :to_hash
          opts = opts.to_hash
        elsif opts.respond_to? :to_h
          opts = opts.to_h
        else
          raise TypeError, "can't convert #{opts.class} into Hash"
        end
        state = state.configure(opts)
      end
      state.generate(obj)
    end

    # :stopdoc:
    # I want to deprecate these later, so I'll first be silent about them, and
    # later delete them.
    alias unparse generate
    module_function :unparse
    # :startdoc:

    # Generate a JSON document from the Ruby data structure _obj_ and return it.
    # This method disables the checks for circles in Ruby objects.
    #
    # *WARNING*: Be careful not to pass any Ruby data structures with circles as
    # _obj_ argument because this will cause JSON to go into an infinite loop.
    def fast_generate(obj, opts = nil)
      if State === opts
        state, opts = opts, nil
      else
        state = FAST_STATE_PROTOTYPE.dup
      end
      if opts
        if opts.respond_to? :to_hash
          opts = opts.to_hash
        elsif opts.respond_to? :to_h
          opts = opts.to_h
        else
          raise TypeError, "can't convert #{opts.class} into Hash"
        end
        state.configure(opts)
      end
      state.generate(obj)
    end

    # :stopdoc:
    # I want to deprecate these later, so I'll first be silent about them, and later delete them.
    alias fast_unparse fast_generate
    module_function :fast_unparse
    # :startdoc:

    # Generate a JSON document from the Ruby data structure _obj_ and return it.
    # The returned document is a prettier form of the document returned by
    # #unparse.
    #
    # The _opts_ argument can be used to configure the generator. See the
    # generate method for a more detailed explanation.
    def pretty_generate(obj, opts = nil)
      if State === opts
        state, opts = opts, nil
      else
        state = PRETTY_STATE_PROTOTYPE.dup
      end
      if opts
        if opts.respond_to? :to_hash
          opts = opts.to_hash
        elsif opts.respond_to? :to_h
          opts = opts.to_h
        else
          raise TypeError, "can't convert #{opts.class} into Hash"
        end
        state.configure(opts)
      end
      state.generate(obj)
    end

    # :stopdoc:
    # I want to deprecate these later, so I'll first be silent about them, and later delete them.
    alias pretty_unparse pretty_generate
    module_function :pretty_unparse
    # :startdoc:

    class << self
      # The global default options for the JSON.load method:
      #  :max_nesting: false
      #  :allow_nan:   true
      #  :quirks_mode: true
      attr_accessor :load_default_options
    end
    self.load_default_options = {
      :max_nesting => false,
      :allow_nan   => true,
      :quirks_mode => true,
    }

    # Load a ruby data structure from a JSON _source_ and return it. A source can
    # either be a string-like object, an IO-like object, or an object responding
    # to the read method. If _proc_ was given, it will be called with any nested
    # Ruby object as an argument recursively in depth first order. The default
    # options for the parser can be changed via the load_default_options method.
    #
    # This method is part of the implementation of the load/dump interface of
    # Marshal and YAML.
    def load(source, proc = nil)
      opts = load_default_options
      if source.respond_to? :to_str
        source = source.to_str
      elsif source.respond_to? :to_io
        source = source.to_io.read
      elsif source.respond_to?(:read)
        source = source.read
      end
      if opts[:quirks_mode] && (source.nil? || source.empty?)
        source = 'null'
      end
      result = parse(source, opts)
      recurse_proc(result, &proc) if proc
      result
    end

    # Recursively calls passed _Proc_ if the parsed data structure is an _Array_ or _Hash_
    def recurse_proc(result, &proc)
      case result
      when Array
        result.each { |x| recurse_proc x, &proc }
        proc.call result
      when Hash
        result.each { |x, y| recurse_proc x, &proc; recurse_proc y, &proc }
        proc.call result
      else
        proc.call result
      end
    end

    alias restore load
    module_function :restore

    class << self
      # The global default options for the JSON.dump method:
      #  :max_nesting: false
      #  :allow_nan:   true
      #  :quirks_mode: true
      attr_accessor :dump_default_options
    end
    self.dump_default_options = {
      :max_nesting => false,
      :allow_nan   => true,
      :quirks_mode => true,
    }

    # Dumps _obj_ as a JSON string, i.e. calls generate on the object and returns
    # the result.
    #
    # If anIO (an IO-like object or an object that responds to the write method)
    # was given, the resulting JSON is written to it.
    #
    # If the number of nested arrays or objects exceeds _limit_, an ArgumentError
    # exception is raised. This argument is similar (but not exactly the
    # same!) to the _limit_ argument in Marshal.dump.
    #
    # The default options for the generator can be changed via the
    # dump_default_options method.
    #
    # This method is part of the implementation of the load/dump interface of
    # Marshal and YAML.
    def dump(obj, anIO = nil, limit = nil)
      if anIO and limit.nil?
        anIO = anIO.to_io if anIO.respond_to?(:to_io)
        unless anIO.respond_to?(:write)
          limit = anIO
          anIO = nil
        end
      end
      opts = JSON.dump_default_options
      limit and opts.update(:max_nesting => limit)
      result = generate(obj, opts)
      if anIO
        anIO.write result
        anIO
      else
        result
      end
    rescue JSON::NestingError
      raise ArgumentError, "exceed depth limit"
    end

    # Swap consecutive bytes of _string_ in place.
    def self.swap!(string) # :nodoc:
      0.upto(string.size / 2) do |i|
        break unless string[2 * i + 1]
        string[2 * i], string[2 * i + 1] = string[2 * i + 1], string[2 * i]
      end
      string
    end

    # Shortuct for iconv.
    if ::String.method_defined?(:encode)
      # Encodes string using Ruby's _String.encode_
      def self.iconv(to, from, string)
        string.encode(to, from)
      end
    else
      require 'iconv'
      # Encodes string using _iconv_ library
      def self.iconv(to, from, string)
        Iconv.conv(to, from, string)
      end
    end

    if ::Object.method(:const_defined?).arity == 1
      def self.const_defined_in?(modul, constant)
        modul.const_defined?(constant)
      end
    else
      def self.const_defined_in?(modul, constant)
        modul.const_defined?(constant, false)
      end
    end
  end

  module ::Kernel
    private

    # Outputs _objs_ to STDOUT as JSON strings in the shortest form, that is in
    # one line.
    def j(*objs)
      objs.each do |obj|
        puts JSON::generate(obj, :allow_nan => true, :max_nesting => false)
      end
      nil
    end

    # Ouputs _objs_ to STDOUT as JSON strings in a pretty format, with
    # indentation and over many lines.
    def jj(*objs)
      objs.each do |obj|
        puts JSON::pretty_generate(obj, :allow_nan => true, :max_nesting => false)
      end
      nil
    end

    # If _object_ is string-like, parse the string and return the parsed result as
    # a Ruby data structure. Otherwise, generate a JSON text from the Ruby data
    # structure object and return it.
    #
    # The _opts_ argument is passed through to generate/parse respectively. See
    # generate and parse for their documentation.
    def JSON(object, *args)
      if object.respond_to? :to_str
        JSON.parse(object.to_str, args.first)
      else
        JSON.generate(object, args.first)
      end
    end
  end

  # Extends any Class to include _json_creatable?_ method.
  class ::Class
    # Returns true if this class can be used to create an instance
    # from a serialised JSON string. The class has to implement a class
    # method _json_create_ that expects a hash as first parameter. The hash
    # should include the required data.
    def json_creatable?
      respond_to?(:json_create)
    end
  end

  JSON.generator = JSON::Pure::Generator
  JSON.parser    = JSON::Pure::Parser
end
module GHI
  module Formatting
    module Colors
      class << self
        attr_accessor :colorize
        def colorize?
          return @colorize if defined? @colorize
          @colorize = STDOUT.tty?
        end
      end

      def colorize?
        Colors.colorize?
      end

      def fg color, &block
        escape color, 3, &block
      end

      def bg color, &block
        fg(offset(color)) { escape color, 4, &block }
      end

      def bright &block
        escape :bright, &block
      end

      def underline &block
        escape :underline, &block
      end

      def blink &block
        escape :blink, &block
      end

      def inverse &block
        escape :inverse, &block
      end

      def no_color
        old_colorize, Colors.colorize = colorize?, false
        yield
      ensure
        Colors.colorize = old_colorize
      end

      def to_hex string
        WEB[string] || string.downcase.sub(/^(#|0x)/, '').
          sub(/^([0-f])([0-f])([0-f])$/, '\1\1\2\2\3\3')
      end

      ANSI = {
        :bright    => 1,
        :underline => 4,
        :blink     => 5,
        :inverse   => 7,

        :black     => 0,
        :red       => 1,
        :green     => 2,
        :yellow    => 3,
        :blue      => 4,
        :magenta   => 5,
        :cyan      => 6,
        :white     => 7
      }

      WEB = {
        'aliceblue'            => 'f0f8ff',
        'antiquewhite'         => 'faebd7',
        'aqua'                 => '00ffff',
        'aquamarine'           => '7fffd4',
        'azure'                => 'f0ffff',
        'beige'                => 'f5f5dc',
        'bisque'               => 'ffe4c4',
        'black'                => '000000',
        'blanchedalmond'       => 'ffebcd',
        'blue'                 => '0000ff',
        'blueviolet'           => '8a2be2',
        'brown'                => 'a52a2a',
        'burlywood'            => 'deb887',
        'cadetblue'            => '5f9ea0',
        'chartreuse'           => '7fff00',
        'chocolate'            => 'd2691e',
        'coral'                => 'ff7f50',
        'cornflowerblue'       => '6495ed',
        'cornsilk'             => 'fff8dc',
        'crimson'              => 'dc143c',
        'cyan'                 => '00ffff',
        'darkblue'             => '00008b',
        'darkcyan'             => '008b8b',
        'darkgoldenrod'        => 'b8860b',
        'darkgray'             => 'a9a9a9',
        'darkgrey'             => 'a9a9a9',
        'darkgreen'            => '006400',
        'darkkhaki'            => 'bdb76b',
        'darkmagenta'          => '8b008b',
        'darkolivegreen'       => '556b2f',
        'darkorange'           => 'ff8c00',
        'darkorchid'           => '9932cc',
        'darkred'              => '8b0000',
        'darksalmon'           => 'e9967a',
        'darkseagreen'         => '8fbc8f',
        'darkslateblue'        => '483d8b',
        'darkslategray'        => '2f4f4f',
        'darkslategrey'        => '2f4f4f',
        'darkturquoise'        => '00ced1',
        'darkviolet'           => '9400d3',
        'deeppink'             => 'ff1493',
        'deepskyblue'          => '00bfff',
        'dimgray'              => '696969',
        'dimgrey'              => '696969',
        'dodgerblue'           => '1e90ff',
        'firebrick'            => 'b22222',
        'floralwhite'          => 'fffaf0',
        'forestgreen'          => '228b22',
        'fuchsia'              => 'ff00ff',
        'gainsboro'            => 'dcdcdc',
        'ghostwhite'           => 'f8f8ff',
        'gold'                 => 'ffd700',
        'goldenrod'            => 'daa520',
        'gray'                 => '808080',
        'green'                => '008000',
        'greenyellow'          => 'adff2f',
        'honeydew'             => 'f0fff0',
        'hotpink'              => 'ff69b4',
        'indianred'            => 'cd5c5c',
        'indigo'               => '4b0082',
        'ivory'                => 'fffff0',
        'khaki'                => 'f0e68c',
        'lavender'             => 'e6e6fa',
        'lavenderblush'        => 'fff0f5',
        'lawngreen'            => '7cfc00',
        'lemonchiffon'         => 'fffacd',
        'lightblue'            => 'add8e6',
        'lightcoral'           => 'f08080',
        'lightcyan'            => 'e0ffff',
        'lightgoldenrodyellow' => 'fafad2',
        'lightgreen'           => '90ee90',
        'lightgray'            => 'd3d3d3',
        'lightgrey'            => 'd3d3d3',
        'lightpink'            => 'ffb6c1',
        'lightsalmon'          => 'ffa07a',
        'lightseagreen'        => '20b2aa',
        'lightskyblue'         => '87cefa',
        'lightslategray'       => '778899',
        'lightslategrey'       => '778899',
        'lightsteelblue'       => 'b0c4de',
        'lightyellow'          => 'ffffe0',
        'lime'                 => '00ff00',
        'limegreen'            => '32cd32',
        'linen'                => 'faf0e6',
        'magenta'              => 'ff00ff',
        'maroon'               => '800000',
        'mediumaquamarine'     => '66cdaa',
        'mediumblue'           => '0000cd',
        'mediumorchid'         => 'ba55d3',
        'mediumpurple'         => '9370db',
        'mediumseagreen'       => '3cb371',
        'mediumslateblue'      => '7b68ee',
        'mediumspringgreen'    => '00fa9a',
        'mediumturquoise'      => '48d1cc',
        'mediumvioletred'      => 'c71585',
        'midnightblue'         => '191970',
        'mintcream'            => 'f5fffa',
        'mistyrose'            => 'ffe4e1',
        'moccasin'             => 'ffe4b5',
        'navajowhite'          => 'ffdead',
        'navy'                 => '000080',
        'oldlace'              => 'fdf5e6',
        'olive'                => '808000',
        'olivedrab'            => '6b8e23',
        'orange'               => 'ffa500',
        'orangered'            => 'ff4500',
        'orchid'               => 'da70d6',
        'palegoldenrod'        => 'eee8aa',
        'palegreen'            => '98fb98',
        'paleturquoise'        => 'afeeee',
        'palevioletred'        => 'db7093',
        'papayawhip'           => 'ffefd5',
        'peachpuff'            => 'ffdab9',
        'peru'                 => 'cd853f',
        'pink'                 => 'ffc0cb',
        'plum'                 => 'dda0dd',
        'powderblue'           => 'b0e0e6',
        'purple'               => '800080',
        'red'                  => 'ff0000',
        'rosybrown'            => 'bc8f8f',
        'royalblue'            => '4169e1',
        'saddlebrown'          => '8b4513',
        'salmon'               => 'fa8072',
        'sandybrown'           => 'f4a460',
        'seagreen'             => '2e8b57',
        'seashell'             => 'fff5ee',
        'sienna'               => 'a0522d',
        'silver'               => 'c0c0c0',
        'skyblue'              => '87ceeb',
        'slateblue'            => '6a5acd',
        'slategray'            => '708090',
        'slategrey'            => '708090',
        'snow'                 => 'fffafa',
        'springgreen'          => '00ff7f',
        'steelblue'            => '4682b4',
        'tan'                  => 'd2b48c',
        'teal'                 => '008080',
        'thistle'              => 'd8bfd8',
        'tomato'               => 'ff6347',
        'turquoise'            => '40e0d0',
        'violet'               => 'ee82ee',
        'wheat'                => 'f5deb3',
        'white'                => 'ffffff',
        'whitesmoke'           => 'f5f5f5',
        'yellow'               => 'ffff00',
        'yellowgreen'          => '9acd32'
      }

      private

      def escape color = :black, layer = nil
        return yield unless color && colorize?
        previous_escape = Thread.current[:escape] || "\e[0m"
        escape = Thread.current[:escape] = "\e[%s%sm" % [
          layer, ANSI[color] || escape_256(color)
        ]
        [escape, yield, previous_escape].join
      ensure
        Thread.current[:escape] = previous_escape
      end

      def escape_256 color
        "8;5;#{to_256(*to_rgb(color))}" if `tput colors` =~ /256/
      end

      def to_256 r, g, b
        r, g, b = [r, g, b].map { |c| c / 10 }
        return 232 + g if r == g && g == b && g != 0 && g != 25
        16 + ((r / 5) * 36) + ((g / 5) * 6) + (b / 5)
      end

      def to_rgb hex
        n = (WEB[hex.to_s] || hex).to_i(16)
        [2, 1, 0].map { |m| n >> (m << 3) & 0xff }
      end

      def offset hex
        h, s, l = rgb_to_hsl(to_rgb(WEB[hex.to_s] || hex))
        l < 55 && !(40..80).include?(h) ? l *= 1.875 : l /= 3
        hsl_to_rgb([h, s, l]).map { |c| '%02x' % c }.join
      end

      def rgb_to_hsl rgb
        r, g, b = rgb.map { |c| c / 255.0 }
        max = [r, g, b].max
        min = [r, g, b].min
        d = max - min
        h = case max
          when min then 0
          when r   then 60 * (g - b) / d
          when g   then 60 * (b - r) / d + 120
          when b   then 60 * (r - g) / d + 240
        end
        l = (max + min) / 2.0
        s = if max == min then 0
          elsif l < 0.5   then d / (2 * l)
          else            d / (2 - 2 * l)
        end
        [h % 360, s * 100, l * 100]
      end

      def hsl_to_rgb hsl
        h, s, l = hsl
        h /= 360.0
        s /= 100.0
        l /= 100.0
        m2 = l <= 0.5 ? l * (s + 1) : l + s - l * s
        m1 = l * 2 - m2
        rgb = [[m1, m2, h + 1.0 / 3], [m1, m2, h], [m1, m2, h - 1.0 / 3]]
        rgb.map { |c|
          m1, m2, h = c
          h += 1 if h < 0
          h -= 1 if h > 1
          next m1 + (m2 - m1) * h * 6 if h * 6 < 1
          next m2 if h * 2 < 1
          next m1 + (m2 - m1) * (2.0/3 - h) * 6 if h * 3 < 2
          m1
        }.map { |c| c * 255 }
      end

      def hue_to_rgb m1, m2, h
        h += 1 if h < 0
        h -= 1 if h > 1
        return m1 + (m2 - m1) * h * 6 if h * 6 < 1
        return m2 if h * 2 < 1
        return m1 + (m2 - m1) * (2.0/3 - h) * 6 if h * 3 < 2
        return m1
      end
    end
  end
end
# encoding: utf-8
require 'date'
require 'erb'

module GHI
  module Formatting
    class << self
      attr_accessor :paginate
    end
    self.paginate = true # Default.
    include Colors

    CURSOR = {
      :up     => lambda { |n| "\e[#{n}A" },
      :column => lambda { |n| "\e[#{n}G" },
      :hide   => "\e[?25l",
      :show   => "\e[?25h"
    }

    THROBBERS = [
      %w(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏),
      %w(⠋ ⠙ ⠚ ⠞ ⠖ ⠦ ⠴ ⠲ ⠳ ⠓),
      %w(⠄ ⠆ ⠇ ⠋ ⠙ ⠸ ⠰ ⠠ ⠰ ⠸ ⠙ ⠋ ⠇ ⠆ ),
      %w(⠋ ⠙ ⠚ ⠒ ⠂ ⠂ ⠒ ⠲ ⠴ ⠦ ⠖ ⠒ ⠐ ⠐ ⠒ ⠓ ⠋),
      %w(⠁ ⠉ ⠙ ⠚ ⠒ ⠂ ⠂ ⠒ ⠲ ⠴ ⠤ ⠄ ⠄ ⠤ ⠴ ⠲ ⠒ ⠂ ⠂ ⠒ ⠚ ⠙ ⠉ ⠁),
      %w(⠈ ⠉ ⠋ ⠓ ⠒ ⠐ ⠐ ⠒ ⠖ ⠦ ⠤ ⠠ ⠠ ⠤ ⠦ ⠖ ⠒ ⠐ ⠐ ⠒ ⠓ ⠋ ⠉ ⠈),
      %w(⠁ ⠁ ⠉ ⠙ ⠚ ⠒ ⠂ ⠂ ⠒ ⠲ ⠴ ⠤ ⠄ ⠄ ⠤ ⠠ ⠠ ⠤ ⠦ ⠖ ⠒ ⠐ ⠐ ⠒ ⠓ ⠋ ⠉ ⠈ ⠈ ⠉)
    ]

    def puts *strings
      strings = strings.flatten.map { |s|
        s.gsub(/(^| )*@([^@\s]+)/) {
          if $2 == Authorization.username
            bright { fg(:yellow) { "#$1@#$2" } }
          else
            bright { "#$1@#$2" }
          end
        }
      }
      super strings
    end

    def page header = nil, throttle = 0
      if paginate?
        pager   = GHI.config('ghi.pager') || GHI.config('core.pager')
        pager ||= ENV['PAGER']
        pager ||= 'less'
        pager  += ' -EKRX -b1' if pager =~ /^less( -[EKRX]+)?$/

        if pager && !pager.empty? && pager != 'cat'
          $stdout = IO.popen pager, 'w'
        end

        puts header if header
      end

      loop do
        yield
        sleep throttle
      end
    rescue Errno::EPIPE
      exit
    ensure
      unless $stdout == STDOUT
        $stdout.close_write
        $stdout = STDOUT
        print CURSOR[:show]
        exit
      end
    end

    def paginate?
      $stdout.tty? && $stdout == STDOUT && Formatting.paginate
    end

    def truncate string, reserved
      result = string.scan(/.{0,#{columns - reserved}}(?:\s|\Z)/).first.strip
      result << "..." if result != string
      result
    end

    def indent string, level = 4, maxwidth = columns
      string = string.gsub(/\r/, '')
      string.gsub!(/[\t ]+$/, '')
      string.gsub!(/\n{3,}/, "\n\n")
      width = maxwidth - level - 1
      lines = string.scan(
        /.{0,#{width}}(?:\s|\Z)|[\S]{#{width},}/ # TODO: Test long lines.
      ).map { |line| " " * level + line.chomp }
      format_markdown lines.join("\n").rstrip, level
    end

    def columns
      dimensions[1] || 80
    end

    def dimensions
      `stty size`.chomp.split(' ').map { |n| n.to_i }
    end

    #--
    # Specific formatters:
    #++

    def format_username username
      username == Authorization.username ? 'you' : username
    end

    def format_issues_header
      state = assigns[:state] || 'open'
      header = "# #{repo || 'Global,'} #{state} issues"
      if repo
        if milestone = assigns[:milestone]
          case milestone
            when '*'    then header << ' with a milestone'
            when 'none' then header << ' without a milestone'
          else
            header.sub! repo, "#{repo} milestone ##{milestone}"
          end
        end
        if assignee = assigns[:assignee]
          header << case assignee
            when '*'    then ', assigned'
            when 'none' then ', unassigned'
          else
            ", assigned to #{format_username assignee}"
          end
        end
        if mentioned = assigns[:mentioned]
          header << ", mentioning #{format_username mentioned}"
        end
      else
        header << case assigns[:filter]
          when 'created'    then ' you created'
          when 'mentioned'  then ' that mention you'
          when 'subscribed' then " you're subscribed to"
        else
          ' assigned to you'
        end
      end
      if creator = assigns[:creator]
        header << " #{format_username creator} created"
      end
      if labels = assigns[:labels]
        header << ", labeled #{labels.gsub ',', ', '}"
      end
      if excluded_labels = assigns[:exclude_labels]
        header << ", excluding those labeled #{excluded_labels.gsub ',', ', '}"
      end
      if sort = assigns[:sort]
        header << ", by #{sort} #{reverse ? 'ascending' : 'descending'}"
      end
      format_state assigns[:state], header
    end

    # TODO: Show milestones.
    def format_issues issues, include_repo
      return 'None.' if issues.empty?

      include_repo and issues.each do |i|
        %r{/repos/[^/]+/([^/]+)} === i['url'] and i['repo'] = $1
      end

      nmax, rmax = %w(number repo).map { |f|
        issues.sort_by { |i| i[f].to_s.size }.last[f].to_s.size
      }

      issues.map { |i|
        n, title, labels = i['number'], i['title'], i['labels']
        l = 9 + nmax + rmax + no_color { format_labels labels }.to_s.length
        a = i['assignee'] && i['assignee']['login'] == Authorization.username
        l += 2 if a
        p = i['pull_request']['html_url'] and l += 2
        c = i['comments']
        l += c.to_s.length + 1 unless c == 0
        [
          " ",
          (i['repo'].to_s.rjust(rmax) if i['repo']),
          format_number(n.to_s.rjust(nmax)),
          truncate(title, l),
          format_labels(labels),
          (fg('aaaaaa') { c } unless c == 0),
          (fg('aaaaaa') { '↑' } if p),
          (fg(:yellow) { '@' } if a)
        ].compact.join ' '
      }
    end

    def format_number n
      colorize? ? "#{bright { n }}:" : "#{n} "
    end

    # TODO: Show milestone, number of comments, pull request attached.
    def format_issue i, width = columns
      return unless i['created_at']
      ERB.new(<<EOF).result binding
<% p = i['pull_request']['html_url'] %>\
<%= bright { no_color { indent '%s%s: %s' % [p ? '↑' : '#', \
*i.values_at('number', 'title')], 0, width } } %>
@<%= i['user']['login'] %> opened this <%= p ? 'pull request' : 'issue' %> \
<%= format_date DateTime.parse(i['created_at']) %>. \
<%= format_state i['state'], format_tag(i['state']), :bg %> \
<% unless i['comments'] == 0 %>\
<%= fg('aaaaaa'){
  template = "%d comment"
  template << "s" unless i['comments'] == 1
  '(' << template % i['comments'] << ')'
} %>\
<% end %>\
<% if i['assignee'] || !i['labels'].empty? %>
<% if i['assignee'] %>@<%= i['assignee']['login'] %> is assigned. <% end %>\
<% unless i['labels'].empty? %><%= format_labels(i['labels']) %><% end %>\
<% end %>\
<% if i['milestone'] %>
Milestone #<%= i['milestone']['number'] %>: <%= i['milestone']['title'] %>\
<%= " \#{bright{fg(:yellow){'⚠'}}}" if past_due? i['milestone'] %>\
<% end %>
<% if i['body'] && !i['body'].empty? %>
<%= indent i['body'], 4, width %>
<% end %>

EOF
    end

    def format_comments comments
      return 'None.' if comments.empty?
      comments.map { |comment| format_comment comment }
    end

    def format_comment c, width = columns
      <<EOF
@#{c['user']['login']} commented \
#{format_date DateTime.parse(c['created_at'])}:
#{indent c['body'], 4, width}


EOF
    end

    def format_milestones milestones
      return 'None.' if milestones.empty?

      max = milestones.sort_by { |m|
        m['number'].to_s.size
      }.last['number'].to_s.size

      milestones.map { |m|
        line = ["  #{m['number'].to_s.rjust max }:"]
        space = past_due?(m) ? 6 : 4
        line << truncate(m['title'], max + space)
        line << '⚠' if past_due? m
        percent m, line.join(' ')
      }
    end

    def format_milestone m, width = columns
      ERB.new(<<EOF).result binding
<%= bright { no_color { \
indent '#%s: %s' % m.values_at('number', 'title'), 0, width } } %>
@<%= m['creator']['login'] %> created this milestone \
<%= format_date DateTime.parse(m['created_at']) %>. \
<%= format_state m['state'], format_tag(m['state']), :bg %>
<% if m['due_on'] %>\
<% due_on = DateTime.parse m['due_on'] %>\
<% if past_due? m %>\
<%= bright{fg(:yellow){"⚠"}} %> \
<%= bright{fg(:red){"Past due by \#{format_date due_on, false}."}} %>
<% else %>\
Due in <%= format_date due_on, false %>.
<% end %>\
<% end %>\
<%= percent m %>
<% if m['description'] && !m['description'].empty? %>
<%= indent m['description'], 4, width %>
<% end %>

EOF
    end

    def past_due? milestone
      return false unless milestone['due_on']
      DateTime.parse(milestone['due_on']) <= DateTime.now
    end

    def percent milestone, string = nil
      open, closed = milestone.values_at('open_issues', 'closed_issues')
      complete = closed.to_f / (open + closed)
      complete = 0 if complete.nan?
      i = (columns * complete).round
      if string.nil?
        string = ' %d%% (%d closed, %d open)' % [complete * 100, closed, open]
      end
      string = string.ljust columns
      [bg('2cc200'){string[0, i]}, string[i, columns - i]].join
    end

    def format_state state, string = state, layer = :fg
      send(layer, state == 'closed' ? 'ff0000' : '2cc200') { string }
    end

    def format_labels labels
      return if labels.empty?
      [*labels].map { |l| bg(l['color']) { format_tag l['name'] } }.join ' '
    end

    def format_tag tag
      (colorize? ? ' %s ' : '[%s]') % tag
    end

    #--
    # Helpers:
    #++

    #--
    # TODO: DRY up editor formatters.
    #++
    def format_editor issue = nil
      message = ERB.new(<<EOF).result binding

Please explain the issue. The first line will become the title. Trailing
lines starting with '#' (like these) will be ignored, and empty messages will
not be submitted. Issues are formatted with GitHub Flavored Markdown (GFM):

  http://github.github.com/github-flavored-markdown

On <%= repo %>

<%= no_color { format_issue issue, columns - 2 if issue } %>
EOF
      message.rstrip!
      message.gsub!(/(?!\A)^.*$/) { |line| "# #{line}".rstrip }
      message.insert 0, [
        issue['title'] || issue[:title], issue['body'] || issue[:body]
      ].compact.join("\n\n") if issue
      message
    end

    def format_milestone_editor milestone = nil
      message = ERB.new(<<EOF).result binding

Describe the milestone. The first line will become the title. Trailing lines
starting with '#' (like these) will be ignored, and empty messages will not be
submitted. Milestones are formatted with GitHub Flavored Markdown (GFM):

  http://github.github.com/github-flavored-markdown

On <%= repo %>

<%= no_color { format_milestone milestone, columns - 2 } if milestone %>
EOF
      message.rstrip!
      message.gsub!(/(?!\A)^.*$/) { |line| "# #{line}".rstrip }
      message.insert 0, [
        milestone['title'], milestone['description']
      ].join("\n\n") if milestone
      message
    end

    def format_comment_editor issue, comment = nil
      message = ERB.new(<<EOF).result binding

Leave a comment. The first line will become the title. Trailing lines starting
with '#' (like these) will be ignored, and empty messages will not be
submitted. Comments are formatted with GitHub Flavored Markdown (GFM):

  http://github.github.com/github-flavored-markdown

On <%= repo %> issue #<%= issue['number'] %>

<%= no_color { format_issue issue } if verbose %>\
<%= no_color { format_comment comment, columns - 2 } if comment %>
EOF
      message.rstrip!
      message.gsub!(/(?!\A)^.*$/) { |line| "# #{line}".rstrip }
      message.insert 0, comment['body'] if comment
      message
    end

    def format_markdown string, indent = 4
      c = '268bd2'

      # Headers.
      string.gsub!(/^( {#{indent}}\#{1,6} .+)$/, bright{'\1'})
      string.gsub!(
        /(^ {#{indent}}.+$\n^ {#{indent}}[-=]+$)/, bright{'\1'}
      )
      # Strong.
      string.gsub!(
        /(^|\s)(\*{2}\w(?:[^*]*\w)?\*{2})(\s|$)/m, '\1' + bright{'\2'} + '\3'
      )
      string.gsub!(
        /(^|\s)(_{2}\w(?:[^_]*\w)?_{2})(\s|$)/m, '\1' + bright {'\2'} + '\3'
      )
      # Emphasis.
      string.gsub!(
        /(^|\s)(\*\w(?:[^*]*\w)?\*)(\s|$)/m, '\1' + underline{'\2'} + '\3'
      )
      string.gsub!(
        /(^|\s)(_\w(?:[^_]*\w)?_)(\s|$)/m, '\1' + underline{'\2'} + '\3'
      )
      # Bullets/Blockquotes.
      string.gsub!(/(^ {#{indent}}(?:[*>-]|\d+\.) )/, fg(c){'\1'})
      # URIs.
      string.gsub!(
        %r{\b(<)?(https?://\S+|[^@\s]+@[^@\s]+)(>)?\b},
        fg(c){'\1' + underline{'\2'} + '\3'}
      )
      # Code.
      # string.gsub!(
      #   /
      #     (^\ {#{indent}}```.*?$)(.+?^\ {#{indent}}```$)|
      #     (^|[^`])(`[^`]+`)([^`]|$)
      #   /mx
      # ) {
      #   post = $5
      #   fg(c){"#$1#$2#$3#$4".gsub(/\e\[[\d;]+m/, '')} + "#{post}"
      # }
      string
    end

    def format_date date, suffix = true
      days = (interval = DateTime.now - date).to_i.abs
      string = if days.zero?
        seconds, _ = interval.divmod Rational(1, 86400)
        hours, seconds = seconds.divmod 3600
        minutes, seconds = seconds.divmod 60
        if hours > 0
          "#{hours} hour#{'s' unless hours == 1}"
        elsif minutes > 0
          "#{minutes} minute#{'s' unless minutes == 1}"
        else
          "#{seconds} second#{'s' unless seconds == 1}"
        end
      else
        "#{days} day#{'s' unless days == 1}"
      end
      ago = interval < 0 ? 'from now' : 'ago' if suffix
      [string, ago].compact.join ' '
    end

    def throb position = 0, redraw = CURSOR[:up][1]
      return yield unless paginate?

      throb = THROBBERS[rand(THROBBERS.length)]
      throb.reverse! if rand > 0.5
      i = rand throb.length

      thread = Thread.new do
        dot = lambda do
          print "\r#{CURSOR[:column][position]}#{throb[i]}#{CURSOR[:hide]}"
          i = (i + 1) % throb.length
          sleep 0.1 and dot.call
        end
        dot.call
      end
      yield
    ensure
      if thread
        thread.kill
        puts "\r#{CURSOR[:column][position]}#{redraw}#{CURSOR[:show]}"
      end
    end
  end
end
# encoding: utf-8

module GHI
  module Authorization
    extend Formatting

    class Required < RuntimeError
      def message() 'Authorization required.' end
    end

    class << self
      def token
        return @token if defined? @token
        @token = GHI.config 'ghi.token'
      end

      def authorize! user = username, pass = password, local = true
        return false unless user && pass
        code ||= nil # 2fa
        args = code ? [] : [54, "✔\r"]
        res = throb(*args) {
          headers = {}
          headers['X-GitHub-OTP'] = code if code
          body = {
            :scopes   => %w(public_repo repo),
            :note     => 'ghi',
            :note_url => 'https://github.com/stephencelis/ghi'
          }
          Client.new(user, pass).post(
            '/authorizations', body, :headers => headers
          )
        }
        @token = res.body['token']

        run = []
        unless username
          run << "git config#{' --global' unless local} github.user #{user}"
        end
        run << "git config#{' --global' unless local} ghi.token #{token}"

        system run.join('; ')

        unless local
          at_exit do
            warn <<EOF
Your ~/.gitconfig has been modified by way of:

  #{run.join "\n  "}

#{bright { blink { 'Do not check this change into public source control!' } }}
Alternatively, set the following env var in a private dotfile:

  export GHI_TOKEN="#{token}"
EOF
          end
        end
      rescue Client::Error => e
        if e.response['X-GitHub-OTP'] =~ /required/
          puts "Bad code." if code
          print "Two-factor authentication code: "
          trap('INT') { abort }
          code = gets
          code = '' and puts "\n" unless code
          retry
        end

        abort "#{e.message}#{CURSOR[:column][0]}"
      end

      def username
        return @username if defined? @username
        @username = GHI.config 'github.user'
      end

      def password
        return @password if defined? @password
        @password = GHI.config 'github.password'
      end
    end
  end
end
require 'cgi'
require 'net/https'

unless defined? Net::HTTP::Patch
  # PATCH support for 1.8.7.
  Net::HTTP::Patch = Class.new(Net::HTTP::Post) { METHOD = 'PATCH' }
end

module GHI
  class Client
    class Error < RuntimeError
      attr_reader :response
      def initialize response
        @response, @json = response, JSON.parse(response.body)
      end

      def body()    @json             end
      def message() body['message']   end
      def errors()  [*body['errors']] end
    end

    class Response
      def initialize response
        @response = response
      end

      def body
        @body ||= JSON.parse @response.body
      end

      def next_page() links['next'] end
      def last_page() links['last'] end

      private

      def links
        return @links if defined? @links
        @links = {}
        if links = @response['Link']
          links.scan(/<([^>]+)>; rel="([^"]+)"/).each { |l, r| @links[r] = l }
        end
        @links
      end
    end

    CONTENT_TYPE = 'application/vnd.github+json'
    USER_AGENT = 'ghi/%s (%s; +%s)' % [
      GHI::Commands::Version::VERSION,
      RUBY_DESCRIPTION,
      'https://github.com/stephencelis/ghi'
    ]
    METHODS = {
      :head   => Net::HTTP::Head,
      :get    => Net::HTTP::Get,
      :post   => Net::HTTP::Post,
      :put    => Net::HTTP::Put,
      :patch  => Net::HTTP::Patch,
      :delete => Net::HTTP::Delete
    }
    DEFAULT_HOST = 'api.github.com'
    HOST = GHI.config('github.host') || DEFAULT_HOST
    PORT = 443

    attr_reader :username, :password
    def initialize username = nil, password = nil
      @username, @password = username, password
    end

    def head path, options = {}
      request :head, path, options
    end

    def get path, params = {}, options = {}
      request :get, path, options.merge(:params => params)
    end

    def post path, body = nil, options = {}
      request :post, path, options.merge(:body => body)
    end

    def put path, body = nil, options = {}
      request :put, path, options.merge(:body => body)
    end

    def patch path, body = nil, options = {}
      request :patch, path, options.merge(:body => body)
    end

    def delete path, options = {}
      request :delete, path, options
    end

    private

    def request method, path, options
      path = "/api/v3#{path}" if HOST != DEFAULT_HOST

      if params = options[:params] and !params.empty?
        q = params.map { |k, v| "#{CGI.escape k.to_s}=#{CGI.escape v.to_s}" }
        path += "?#{q.join '&'}"
      end

      headers = options.fetch :headers, {}
      headers.update 'Accept' => CONTENT_TYPE, 'User-Agent' => USER_AGENT
      req = METHODS[method].new path, headers
      if GHI::Authorization.token
        req['Authorization'] = "token #{GHI::Authorization.token}"
      end
      if options.key? :body
        req['Content-Type'] = CONTENT_TYPE
        req.body = options[:body] ? JSON.dump(options[:body]) : ''
      end
      req.basic_auth username, password if username && password

      proxy   = GHI.config 'https.proxy', :upcase => false
      proxy ||= GHI.config 'http.proxy',  :upcase => false
      if proxy
        proxy = URI.parse proxy
        http = Net::HTTP::Proxy(proxy.host, proxy.port).new HOST, PORT
      else
        http = Net::HTTP.new HOST, PORT
      end

      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE # FIXME 1.8.7

      GHI.v? and puts "\r===> #{method.to_s.upcase} #{path} #{req.body}"
      res = http.start { http.request req }
      GHI.v? and puts "\r<=== #{res.code}: #{res.body}"

      case res
      when Net::HTTPSuccess
        return Response.new(res)
      when Net::HTTPUnauthorized
        if password.nil?
          raise Authorization::Required, 'Authorization required'
        end
      end

      raise Error, res
    end
  end
end
require 'tmpdir'

module GHI
  class Editor
    attr_reader :filename
    def initialize filename
      @filename = filename
    end

    def gets prefill
      File.open path, 'a+' do |f|
        f << prefill if File.zero? path
        f.rewind
        system "#{editor} #{f.path}"
        return File.read(f.path).gsub(/(?:^#.*$\n?)+\s*\z/, '').strip
      end
    end

    def unlink message = nil
      File.delete path
      abort message if message
    end

    private

    def editor
      editor   = GHI.config 'ghi.editor'
      editor ||= GHI.config 'core.editor'
      editor ||= ENV['VISUAL']
      editor ||= ENV['EDITOR']
      editor ||= 'vi'
    end

    def path
      File.join dir, filename
    end

    def dir
      @dir ||= git_dir || Dir.tmpdir
    end

    def git_dir
      return unless Commands::Command.detected_repo
      dir = `git rev-parse --git-dir 2>/dev/null`.chomp
      dir unless dir.empty?
    end
  end
end
require 'open-uri'
require 'uri'

module GHI
  class Web
    HOST = GHI.config('github.host') || 'github.com'
    BASE_URI = "https://#{HOST}/"

    attr_reader :base
    def initialize base
      @base = base
    end

    def open path = '', params = {}
      launcher = 'open'
      launcher = 'xdg-open' if /linux/ =~ RUBY_PLATFORM
      system "#{launcher} '#{uri_for path, params}'"
    end

    def curl path = '', params = {}
      uri_for(path, params).open.read
    end

    private

    def uri_for path, params
      unless params.empty?
        q = params.map { |k, v| "#{CGI.escape k.to_s}=#{CGI.escape v.to_s}" }
        path += "?#{q.join '&'}"
      end
      URI(BASE_URI) + "#{base}/" + path
    end
  end
end
module GHI
  module Commands
  end
end
module GHI
  module Commands
    class MissingArgument < RuntimeError
    end

    class Command
      include Formatting

      class << self
        attr_accessor :detected_repo

        def execute args
          command = new args
          if i = args.index('--')
            command.repo = args.slice!(i, args.length)[1] # Raise if too many?
          end
          command.execute
        end
      end

      attr_reader :args
      attr_writer :issue
      attr_accessor :action
      attr_accessor :verbose

      def initialize args
        @args = args.map! { |a| a.dup }
      end

      def assigns
        @assigns ||= {}
      end

      def api
        @api ||= Client.new
      end

      def repo
        return @repo if defined? @repo
        @repo = GHI.config('ghi.repo', :flags => '--local') || detect_repo
        if @repo && !@repo.include?('/')
          @repo = [Authorization.username, @repo].join '/'
        end
        @repo
      end
      alias extract_repo repo

      def repo= repo
        @repo = repo.dup
        unless @repo.include? '/'
          @repo.insert 0, "#{Authorization.username}/"
        end
        @repo
      end

      private

      def require_repo
        return true if repo
        warn 'Not a GitHub repo.'
        warn ''
        abort options.to_s
      end

      def detect_repo
        remote   = remotes.find { |r| r[:remote] == 'upstream' }
        remote ||= remotes.find { |r| r[:remote] == 'origin' }
        remote ||= remotes.find { |r| r[:user]   == Authorization.username }
        Command.detected_repo = true and remote[:repo] if remote
      end

      def remotes
        return @remotes if defined? @remotes
        @remotes = `git config --get-regexp remote\..+\.url`.split "\n"
        github_host = GHI.config('github.host') || 'github.com'
        @remotes.reject! { |r| !r.include? github_host}
        @remotes.map! { |r|
          remote, user, repo = r.scan(
            %r{remote\.([^\.]+)\.url .*?([^:/]+)/([^/\s]+?)(?:\.git)?$}
          ).flatten
          { :remote => remote, :user => user, :repo => "#{user}/#{repo}" }
        }
        @remotes
      end

      def issue
        return @issue if defined? @issue
        index = args.index { |arg| /^\d+$/ === arg }
        @issue = (args.delete_at index if index)
      end
      alias extract_issue     issue
      alias milestone         issue
      alias extract_milestone issue

      def require_issue
        raise MissingArgument, 'Issue required.' unless issue
      end

      def require_milestone
        raise MissingArgument, 'Milestone required.' unless milestone
      end

      # Handles, e.g. `--[no-]milestone [<n>]`.
      def any_or_none_or input
        input ? input : { nil => '*', false => 'none' }[input]
      end
    end
  end
end
module GHI
  module Commands
    class Assign < Command
      def options
        OptionParser.new do |opts|
          opts.banner = <<EOF
usage: ghi assign [options] [<issueno>]
   or: ghi assign <issueno> <user>
   or: ghi unassign <issueno>
EOF
          opts.separator ''
          opts.on(
            '-u', '--assignee <user>', 'assign to specified user'
          ) do |assignee|
            assigns[:assignee] = assignee
          end
          opts.on '-d', '--no-assignee', 'unassign this issue' do
            assigns[:assignee] = nil
          end
          opts.on '-l', '--list', 'list assigned issues' do
            self.action = 'list'
          end
          opts.separator ''
        end
      end

      def execute
        self.action = 'edit'
        assigns[:args] = []

        require_repo
        extract_issue
        options.parse! args

        unless assigns.key? :assignee
          assigns[:assignee] = args.pop || Authorization.username
        end
        if assigns.key? :assignee
          assigns[:assignee].sub! /^@/, ''
          assigns[:args].concat(
            assigns[:assignee] ? %W(-u #{assigns[:assignee]}) : %w(--no-assign)
          )
        end
        assigns[:args] << issue if issue
        assigns[:args].concat %W(-- #{repo})

        case action
          when 'list' then List.execute assigns[:args]
          when 'edit' then Edit.execute assigns[:args]
        end
      end
    end
  end
end
module GHI
  module Commands
    class Close < Command
      attr_accessor :web

      def options
        OptionParser.new do |opts|
          opts.banner = <<EOF
usage: ghi close [options] <issueno>
EOF
          opts.separator ''
          opts.on '-l', '--list', 'list closed issues' do
            assigns[:command] = List
          end
          opts.on('-w', '--web') { self.web = true }
          opts.separator ''
          opts.separator 'Issue modification options'
          opts.on '-m', '--message [<text>]', 'close with message' do |text|
            assigns[:comment] = text
          end
          opts.separator ''
        end
      end

      def execute
        options.parse! args
        require_repo

        if list?
          args.unshift(*%W(-sc -- #{repo}))
          args.unshift '-w' if web
          List.execute args
        else
          require_issue
          if assigns.key? :comment
            Comment.execute [
              issue, '-m', assigns[:comment], '--', repo
            ].compact
          end
          Edit.execute %W(-sc #{issue} -- #{repo})
        end
      end

      private

      def list?
        assigns[:command] == List
      end
    end
  end
end
module GHI
  module Commands
    class Comment < Command
      attr_accessor :comment
      attr_accessor :verbose
      attr_accessor :web

      def options
        OptionParser.new do |opts|
          opts.banner = <<EOF
usage: ghi comment [options] <issueno>
EOF
          opts.separator ''
          opts.on '-l', '--list', 'list comments' do
            self.action = 'list'
          end
          opts.on('-w', '--web') { self.web = true }
          # opts.on '-v', '--verbose', 'list events, too'
          opts.separator ''
          opts.separator 'Comment modification options'
          opts.on '-m', '--message [<text>]', 'comment body' do |text|
            assigns[:body] = text
          end
          opts.on '--amend', 'amend previous comment' do
            self.action = 'update'
          end
          opts.on '-D', '--delete', 'delete previous comment' do
            self.action = 'destroy'
          end
          opts.on '--close', 'close associated issue' do
            self.action = 'close'
          end
          opts.on '-v', '--verbose' do
            self.verbose = true
          end
          opts.separator ''
        end
      end

      def execute
        require_issue
        require_repo
        self.action ||= 'create'
        options.parse! args

        case action
        when 'list'
          res = index
          page do
            puts format_comments(res.body)
            break unless res.next_page
            res = throb { api.get res.next_page }
          end
        when 'create'
          if web
            Web.new(repo).open "issues/#{issue}#issue_comment_form"
          else
            create
          end
        when 'update', 'destroy'
          res = index
          res = throb { api.get res.last_page } if res.last_page
          self.comment = res.body.reverse.find { |c|
            c['user']['login'] == Authorization.username
          }
          if comment
            send action
          else
            abort 'No recent comment found.'
          end
        when 'close'
          Close.execute [issue, '-m', assigns[:body], '--', repo].compact
        end
      end

      protected

      def index
        throb { api.get uri, :per_page => 100 }
      end

      def create message = 'Commented.'
        e = require_body
        c = throb { api.post uri, assigns }.body
        puts format_comment(c)
        puts message
        e.unlink if e
      end

      def update
        create 'Comment updated.'
      end

      def destroy
        throb { api.delete uri }
        puts 'Comment deleted.'
      end

      private

      def uri
        if comment
          comment['url']
        else
          "/repos/#{repo}/issues/#{issue}/comments"
        end
      end

      def require_body
        assigns[:body] = args.join ' ' unless args.empty?
        return if assigns[:body]
        if issue && verbose
          i = throb { api.get "/repos/#{repo}/issues/#{issue}" }.body
        else
          i = {'number'=>issue}
        end
        filename = "GHI_COMMENT_#{issue}"
        filename << "_#{comment['id']}" if comment
        e = Editor.new filename
        message = e.gets format_comment_editor(i, comment)
        e.unlink 'No comment.' if message.nil? || message.empty?
        if comment && message.strip == comment['body'].strip
          e.unlink 'No change.'
        end
        assigns[:body] = message if message
        e
      end
    end
  end
end
module GHI
  module Commands
    class Config < Command
      def options
        OptionParser.new do |opts|
          opts.banner = <<EOF
usage: ghi config [options]
EOF
          opts.separator ''
          opts.on '--local', 'set for local repo only' do
            assigns[:local] = true
          end
          opts.on '--auth [<username>]' do |username|
            self.action = 'auth'
            assigns[:username] = username || Authorization.username
          end
          opts.separator ''
        end
      end

      def execute
        global = true
        options.parse! args.empty? ? %w(-h) : args

        if action == 'auth'
          assigns[:password] = Authorization.password || get_password
          Authorization.authorize!(
            assigns[:username], assigns[:password], assigns[:local]
          )
        end
      end

      private

      def get_password
        print "Enter #{assigns[:username]}'s GitHub password (never stored): "
        current_tty = `stty -g`
        system 'stty raw -echo -icanon isig' if $?.success?
        input = ''
        while char = $stdin.getbyte and not (char == 13 or char == 10)
          if char == 127 or char == 8
            input[-1, 1] = '' unless input.empty?
          else
            input << char.chr
          end
        end
        input
      rescue Interrupt
        print '^C'
      ensure
        system "stty #{current_tty}" unless current_tty.empty?
      end
    end
  end
end
module GHI
  module Commands
    class Edit < Command
      attr_accessor :editor

      def options
        OptionParser.new do |opts|
          opts.banner = <<EOF
usage: ghi edit [options] <issueno>
EOF
          opts.separator ''
          opts.on(
            '-m', '--message [<text>]', 'change issue description'
          ) do |text|
            next self.editor = true if text.nil?
            assigns[:title], assigns[:body] = text.split(/\n+/, 2)
          end
          opts.on(
            '-u', '--[no-]assign [<user>]', 'assign to specified user'
          ) do |assignee|
            assigns[:assignee] = assignee
          end
          opts.on '--claim', 'assign to yourself' do
            assigns[:assignee] = Authorization.username
          end
          opts.on(
            '-s', '--state <in>', %w(open closed),
            {'o'=>'open', 'c'=>'closed'}, "'open' or 'closed'"
          ) do |state|
            assigns[:state] = state
          end
          opts.on(
            '-M', '--[no-]milestone [<n>]', Integer, 'associate with milestone'
          ) do |milestone|
            assigns[:milestone] = milestone
          end
          opts.on(
            '-L', '--label <labelname>...', Array, 'associate with label(s)'
          ) do |labels|
            (assigns[:labels] ||= []).concat labels
          end
          opts.separator ''
          opts.separator 'Pull request options'
          opts.on(
            '-H', '--head [[<user>:]<branch>]',
            'branch where your changes are implemented',
            '(defaults to current branch)'
          ) do |head|
            self.action = 'pull'
            assigns[:head] = head
          end
          opts.on(
            '-b', '--base [<branch>]',
            'branch you want your changes pulled into', '(defaults to master)'
          ) do |base|
            self.action = 'pull'
            assigns[:base] = base
          end
          opts.separator ''
        end
      end

      def execute
        self.action = 'edit'
        require_repo
        require_issue
        options.parse! args
        case action
        when 'edit'
          begin
            if editor || assigns.empty?
              i = throb { api.get "/repos/#{repo}/issues/#{issue}" }.body
              e = Editor.new "GHI_ISSUE_#{issue}"
              message = e.gets format_editor(i)
              e.unlink "There's no issue." if message.nil? || message.empty?
              assigns[:title], assigns[:body] = message.split(/\n+/, 2)
            end
            if i && assigns.keys.map { |k| k.to_s }.sort == %w[body title]
              titles_match = assigns[:title].strip == i['title'].strip
              if assigns[:body]
                bodies_match = assigns[:body].to_s.strip == i['body'].to_s.strip
              end
              if titles_match && bodies_match
                e.unlink if e
                abort 'No change.' if assigns.dup.delete_if { |k, v|
                  [:title, :body].include? k
                }
              end
            end
            unless assigns.empty?
              i = throb {
                api.patch "/repos/#{repo}/issues/#{issue}", assigns
              }.body
              puts format_issue(i)
              puts 'Updated.'
            end
            e.unlink if e
          rescue Client::Error => e
            raise unless error = e.errors.first
            abort "%s %s %s %s." % [
              error['resource'],
              error['field'],
              [*error['value']].join(', '),
              error['code']
            ]
          end
        when 'pull'
          begin
            assigns[:issue] = issue
            assigns[:base] ||= 'master'
            head = begin
              if ref = %x{
                git rev-parse --abbrev-ref HEAD@{upstream} 2>/dev/null
              }.chomp!
                ref.split('/').last if $? == 0
              end
            end
            assigns[:head] ||= head
            if assigns[:head]
              assigns[:head].sub!(/:$/, ":#{head}")
            else
              abort <<EOF.chomp
fatal: HEAD can't be null. (Is your current branch being tracked upstream?)
EOF
            end
            throb { api.post "/repos/#{repo}/pulls", assigns }
            base = [repo.split('/').first, assigns[:base]].join ':'
            puts 'Issue #%d set up to track remote branch %s against %s.' % [
              issue, assigns[:head], base
            ]
          rescue Client::Error => e
            raise unless error = e.errors.last
            abort error['message'].sub(/^base /, '')
          end
        end
      end
    end
  end
end
module GHI
  module Commands
    class Help < Command
      def self.execute args, message = nil
        new(args).execute message
      end

      attr_accessor :command

      def options
        OptionParser.new do |opts|
          opts.banner = 'usage: ghi help [--all] [--man|--web] <command>'
          opts.separator ''
          opts.on('-a', '--all', 'print all available commands') { all }
          opts.on('-m', '--man', 'show man page')                { man }
          opts.on('-w', '--web', 'show manual in web browser')   { web }
          opts.separator ''
        end
      end

      def execute message = nil
        self.command = args.shift if args.first !~ /^-/

        if command.nil? && args.empty?
          puts message if message
          puts <<EOF

The most commonly used ghi commands are:
   list        List your issues (or a repository's)
   show        Show an issue's details
   open        Open (or reopen) an issue
   close       Close an issue
   edit        Modify an existing issue
   comment     Leave a comment on an issue
   label       Create, list, modify, or delete labels
   assign      Assign an issue to yourself (or someone else)
   milestone   Manage project milestones

See 'ghi help <command>' for more information on a specific command.
EOF
          exit
        end

        options.parse! args.empty? ? %w(-m) : args
      end

      def all
        raise 'TODO'
      end

      def man
        GHI.execute [command, '-h']
        # TODO:
        # exec "man #{['ghi', command].compact.join '-'}"
      end

      def web
        raise 'TODO'
      end
    end
  end
end
module GHI
  module Commands
    class Label < Command
      attr_accessor :name

      #--
      # FIXME: This does too much. Opt for a secondary command, e.g.,
      #
      #   ghi label add <labelname>
      #   ghi label rm <labelname>
      #   ghi label <issueno> <labelname>...
      #++
      def options
        OptionParser.new do |opts|
          opts.banner = <<EOF
usage: ghi label <labelname> [-c <color>] [-r <newname>]
   or: ghi label -D <labelname>
   or: ghi label <issueno> [-a] [-d] [-f]
   or: ghi label -l [<issueno>]
EOF
          opts.separator ''
          opts.on '-l', '--list [<issueno>]', 'list label names' do |n|
            self.action = 'index'
            @issue ||= n
          end
          opts.on '-D', '--delete', 'delete label' do
            self.action = 'destroy'
          end
          opts.separator ''
          opts.separator 'Label modification options'
          opts.on(
            '-c', '--color <color>', 'color name or 6-character hex code'
          ) do |color|
            assigns[:color] = to_hex color
            self.action ||= 'create'
          end
          opts.on '-r', '--rename <labelname>', 'new label name' do |name|
            assigns[:name] = name
            self.action = 'update'
          end
          opts.separator ''
          opts.separator 'Issue modification options'
          opts.on '-a', '--add', 'add labels to issue' do
            self.action = issue ? 'add' : 'create'
          end
          opts.on '-d', '--delete', 'remove labels from issue' do
            self.action = issue ? 'remove' : 'destroy'
          end
          opts.on '-f', '--force', 'replace existing labels' do
            self.action = issue ? 'replace' : 'update'
          end
          opts.separator ''
        end
      end

      def execute
        extract_issue
        require_repo
        options.parse! args.empty? ? %w(-l) : args

        if issue
          self.action ||= 'add'
          self.name = args.shift.to_s.split ','
          self.name.concat args
        else
          self.action ||= 'create'
          self.name ||= args.shift
        end

        send action
      end

      protected

      def index
        if issue
          uri = "/repos/#{repo}/issues/#{issue}/labels"
        else
          uri = "/repos/#{repo}/labels"
        end
        labels = throb { api.get uri }.body
        if labels.empty?
          puts 'None.'
        else
          puts labels.map { |label|
            name = label['name']
            colorize? ? bg(label['color']) { " #{name} " } : name
          }
        end
      end

      def create
        label = throb {
          api.post "/repos/#{repo}/labels", assigns.merge(:name => name)
        }.body
        return update if label.nil?
        puts "%s created." % bg(label['color']) { " #{label['name']} "}
      rescue Client::Error => e
        if e.errors.find { |error| error['code'] == 'already_exists' }
          return update
        end
        raise
      end

      def update
        label = throb {
          api.patch "/repos/#{repo}/labels/#{name}", assigns
        }.body
        puts "%s updated." % bg(label['color']) { " #{label['name']} "}
      end

      def destroy
        throb { api.delete "/repos/#{repo}/labels/#{name}" }
        puts "[#{name}] deleted."
      end

      def add
        labels = throb {
          api.post "/repos/#{repo}/issues/#{issue}/labels", name
        }.body
        puts "Issue #%d labeled %s." % [issue, format_labels(labels)]
      end

      def remove
        case name.length
        when 0
          throb { api.delete base_uri }
          puts "Labels removed."
        when 1
          labels = throb { api.delete "#{base_uri}/#{name.join}" }.body
          if labels.empty?
            puts "Issue #%d unlabeled." % issue
          else
            puts "Issue #%d labeled %s." % [issue, format_labels(labels)]
          end
        else
          labels = throb {
            api.get "/repos/#{repo}/issues/#{issue}/labels"
          }.body
          self.name = labels.map { |l| l['name'] } - name
          replace
        end
      end

      def replace
        labels = throb { api.put base_uri, name }.body
        if labels.empty?
          puts "Issue #%d unlabeled." % issue
        else
          puts "Issue #%d labeled %s." % [issue, format_labels(labels)]
        end
      end

      private

      def base_uri
        "/repos/#{repo}/#{issue ? "issues/#{issue}/labels" : 'labels'}"
      end
    end
  end
end
require 'date'

module GHI
  module Commands
    class List < Command
      attr_accessor :web
      attr_accessor :reverse
      attr_accessor :quiet
      attr_accessor :exclude_pull_requests

      def options
        OptionParser.new do |opts|
          opts.banner = 'usage: ghi list [options]'
          opts.separator ''
          opts.on '-a', '--global', '--all', 'all of your issues on GitHub' do
            @repo = nil
          end
          opts.on(
            '-s', '--state <in>', %w(open closed),
            {'o'=>'open', 'c'=>'closed'}, "'open' or 'closed'"
          ) do |state|
            assigns[:state] = state
          end
          opts.on(
            '-L', '--label <labelname>...', Array, 'by label(s)'
          ) do |labels|
            (assigns[:labels] ||= []).concat labels
          end
          opts.on(
            '-N', '--not-label <labelname>...', Array, 'exclude with label(s)'
          ) do |labels|
            (assigns[:exclude_labels] ||= []).concat labels
          end
          opts.on(
            '-S', '--sort <by>', %w(created updated comments),
            {'c'=>'created','u'=>'updated','m'=>'comments'},
            "'created', 'updated', or 'comments'"
          ) do |sort|
            assigns[:sort] = sort
          end
          opts.on '--reverse', 'reverse (ascending) sort order' do
            self.reverse = !reverse
          end
          opts.on('-p', '--no-pulls','exclude pull requests') { self.exclude_pull_requests = true }
          opts.on(
            '--since <date>', 'issues more recent than',
            "e.g., '2011-04-30'"
          ) do |date|
            begin
              assigns[:since] = DateTime.parse date # TODO: Better parsing.
            rescue ArgumentError => e
              raise OptionParser::InvalidArgument, e.message
            end
          end
          opts.on('-v', '--verbose') { self.verbose = true }
          opts.on('-w', '--web') { self.web = true }
          opts.separator ''
          opts.separator 'Global options'
          opts.on(
            '-f', '--filter <by>',
            filters = %w(assigned created mentioned subscribed),
            Hash[filters.map { |f| [f[0, 1], f] }],
            "'assigned', 'created', 'mentioned', or", "'subscribed'"
          ) do |filter|
            assigns[:filter] = filter
          end
          opts.separator ''
          opts.separator 'Project options'
          opts.on(
            '-M', '--[no-]milestone [<n>]', Integer,
            'with (specified) milestone'
          ) do |milestone|
            assigns[:milestone] = any_or_none_or milestone
          end
          opts.on(
            '-u', '--[no-]assignee [<user>]', 'assigned to specified user'
          ) do |assignee|
            assignee = assignee.sub /^@/, '' if assignee
            assigns[:assignee] = any_or_none_or assignee
          end
          opts.on '--mine', 'assigned to you' do
            assigns[:assignee] = Authorization.username
          end
          opts.on(
            '--creator [<user>]', 'created by you or specified user'
          ) do |creator|
            creator = creator.sub /^@/, '' if creator
            assigns[:creator] = creator || Authorization.username
          end
          opts.on(
            '-U', '--mentioned [<user>]', 'mentioning you or specified user'
          ) do |mentioned|
            assigns[:mentioned] = mentioned || Authorization.username
          end
          opts.separator ''
        end
      end

      def execute
        if index = args.index { |arg| /^@/ === arg }
          assigns[:assignee] = args.delete_at(index)[1..-1]
        end

        begin
          options.parse! args
          @repo ||= ARGV[0] if ARGV.one?
        rescue OptionParser::InvalidOption => e
          fallback.parse! e.args
          retry
        end
        assigns[:labels] = assigns[:labels].join ',' if assigns[:labels]
        if assigns[:exclude_labels]
          assigns[:exclude_labels] = assigns[:exclude_labels].join ','
        end
        if reverse
          assigns[:sort] ||= 'created'
          assigns[:direction] = 'asc'
        end
        if web
          Web.new(repo || 'dashboard').open 'issues', assigns
        else
          assigns[:per_page] = 100
          unless quiet
            print header = format_issues_header
            print "\n" unless paginate?
          end
          res = throb(
            0, format_state(assigns[:state], quiet ? CURSOR[:up][1] : '#')
          ) { api.get uri, assigns }
          print "\r#{CURSOR[:up][1]}" if header && paginate?
          page header do
            issues = res.body
            if exclude_pull_requests
              issues = issues.reject {|i| i["pull_request"].any? {|k,v| !v.nil? } }
            end
            if assigns[:exclude_labels]
              issues = issues.reject  do |i|
                i["labels"].any? do |label|
                  assigns[:exclude_labels].include? label["name"]
                end
              end
            end
            if verbose
              puts issues.map { |i| format_issue i }
            else
              puts format_issues(issues, repo.nil?)
            end
            break unless res.next_page
            res = throb { api.get res.next_page }
          end
        end
      rescue Client::Error => e
        if e.response.code == '422'
          e.errors.any? { |err|
            err['code'] == 'missing' && err['field'] == 'milestone'
          } and abort 'No such milestone.'
        end

        raise
      end

      private

      def uri
        (repo ? "/repos/#{repo}" : '') << '/issues'
      end

      def fallback
        OptionParser.new do |opts|
          opts.on('-c', '--closed') { assigns[:state] = 'closed' }
          opts.on('-q', '--quiet')  { self.quiet = true }
        end
      end
    end
  end
end
require 'date'

module GHI
  module Commands
    class Milestone < Command
      attr_accessor :edit
      attr_accessor :reverse
      attr_accessor :web

      #--
      # FIXME: Opt for better interface, e.g.,
      #
      #   ghi milestone [-v | --verbose] [--[no-]closed]
      #   ghi milestone add <name> <description>
      #   ghi milestone rm <milestoneno>
      #++
      def options
        OptionParser.new do |opts|
          opts.banner = <<EOF
usage: ghi milestone [<modification options>] [<milestoneno>]
   or: ghi milestone -D <milestoneno>
   or: ghi milestone -l [-c] [-v]
EOF
          opts.separator ''
          opts.on '-l', '--list', 'list milestones' do
            self.action = 'index'
          end
          opts.on '-c', '--[no-]closed', 'show closed milestones' do |closed|
            assigns[:state] = closed ? 'closed' : 'open'
          end
          opts.on(
            '-S', '--sort <on>', %w(due_date completeness),
            {'d'=>'due_date', 'due'=>'due_date', 'c'=>'completeness'},
            "'due_date' or 'completeness'"
          ) do |sort|
            assigns[:sort] = sort
          end
          opts.on '--reverse', 'reverse (ascending) sort order' do
            self.reverse = !reverse
          end
          opts.on '-v', '--verbose', 'list milestones verbosely' do
            self.verbose = true
          end
          opts.on('-w', '--web') { self.web = true }
          opts.separator ''
          opts.separator 'Milestone modification options'
          opts.on(
            '-m', '--message [<text>]', 'change milestone description'
          ) do |text|
            self.action = 'create'
            self.edit = true
            next unless text
            assigns[:title], assigns[:description] = text.split(/\n+/, 2)
          end
          # FIXME: We already describe --[no-]closed; describe this, too?
          opts.on(
            '-s', '--state <in>', %w(open closed),
            {'o'=>'open', 'c'=>'closed'}, "'open' or 'closed'"
          ) do |state|
            self.action = 'create'
            assigns[:state] = state
          end
          opts.on(
            '--due <on>', 'when milestone should be complete',
            "e.g., '2012-04-30'"
          ) do |date|
            self.action = 'create'
            begin
              # TODO: Better parsing.
              assigns[:due_on] = DateTime.parse(date).strftime
            rescue ArgumentError => e
              raise OptionParser::InvalidArgument, e.message
            end
          end
          opts.on '-D', '--delete', 'delete milestone' do
            self.action = 'destroy'
          end
          opts.separator ''
        end
      end

      def execute
        self.action = 'index'
        require_repo
        extract_milestone

        begin
          options.parse! args
        rescue OptionParser::AmbiguousOption => e
          fallback.parse! e.args
        end

        milestone and case action
          when 'create' then self.action = 'update'
          when 'index'  then self.action = 'show'
        end

        if reverse
          assigns[:sort] ||= 'created'
          assigns[:direction] = 'asc'
        end

        case action
        when 'index'
          if web
            Web.new(repo).open 'issues/milestones', assigns
          else
            assigns[:per_page] = 100
            state = assigns[:state] || 'open'
            print format_state state, "# #{repo} #{state} milestones"
            print "\n" unless paginate?
            res = throb(0, format_state(state, '#')) { api.get uri, assigns }
            page do
              milestones = res.body
              if verbose
                puts milestones.map { |m| format_milestone m }
              else
                puts format_milestones(milestones)
              end
              break unless res.next_page
              res = throb { api.get res.next_page }
            end
          end
        when 'show'
          if web
            List.execute %W(-w -M #{milestone} -- #{repo})
          else
            m = throb { api.get uri }.body
            page do
              puts format_milestone(m)
              puts 'Issues:'
              args.unshift(*%W(-q -M #{milestone} -- #{repo}))
              args.unshift '-v' if verbose
              List.execute args
              break
            end
          end
        when 'create'
          if web
            Web.new(repo).open 'issues/milestones/new'
          else
            if assigns[:title].nil?
              e = Editor.new 'GHI_MILESTONE'
              message = e.gets format_milestone_editor
              e.unlink 'Empty milestone.' if message.nil? || message.empty?
              assigns[:title], assigns[:description] = message.split(/\n+/, 2)
            end
            m = throb { api.post uri, assigns }.body
            puts 'Milestone #%d created.' % m['number']
            e.unlink if e
          end
        when 'update'
          if web
            Web.new(repo).open "issues/milestones/#{milestone}/edit"
          else
            if edit || assigns.empty?
              m = throb { api.get "/repos/#{repo}/milestones/#{milestone}" }.body
              e = Editor.new "GHI_MILESTONE_#{milestone}"
              message = e.gets format_milestone_editor(m)
              e.unlink 'Empty milestone.' if message.nil? || message.empty?
              assigns[:title], assigns[:description] = message.split(/\n+/, 2)
            end
            if assigns[:title] && m
              t_match = assigns[:title].strip == m['title'].strip
              if assigns[:description]
                b_match = assigns[:description].strip == m['description'].strip
              end
              if t_match && b_match
                e.unlink if e
                abort 'No change.' if assigns.dup.delete_if { |k, v|
                  [:title, :description].include? k
                }
              end
            end
            m = throb { api.patch uri, assigns }.body
            puts format_milestone(m)
            puts 'Updated.'
            e.unlink if e
          end
        when 'destroy'
          require_milestone
          throb { api.delete uri }
          puts 'Milestone deleted.'
        end
      end

      private

      def uri
        if milestone
          "/repos/#{repo}/milestones/#{milestone}"
        else
          "/repos/#{repo}/milestones"
        end
      end

      def fallback
        OptionParser.new do |opts|
          opts.on '-d' do
            self.action = 'destroy'
          end
        end
      end
    end
  end
end
module GHI
  module Commands
    class Open < Command
      attr_accessor :editor
      attr_accessor :web

      def options
        OptionParser.new do |opts|
          opts.banner = <<EOF
usage: ghi open [options]
   or: ghi reopen [options] <issueno>
EOF
          opts.separator ''
          opts.on '-l', '--list', 'list open tickets' do
            self.action = 'index'
          end
          opts.on('-w', '--web') { self.web = true }
          opts.separator ''
          opts.separator 'Issue modification options'
          opts.on '-m', '--message [<text>]', 'describe issue' do |text|
            if text
              assigns[:title], assigns[:body] = text.split(/\n+/, 2)
            else
              self.editor = true
            end
          end
          opts.on(
            '-u', '--[no-]assign [<user>]', 'assign to specified user'
          ) do |assignee|
            assigns[:assignee] = assignee
          end
          opts.on '--claim', 'assign to yourself' do
            assigns[:assignee] = Authorization.username
          end
          opts.on(
            '-M', '--milestone <n>', 'associate with milestone'
          ) do |milestone|
            assigns[:milestone] = milestone
          end
          opts.on(
            '-L', '--label <labelname>...', Array, 'associate with label(s)'
          ) do |labels|
            (assigns[:labels] ||= []).concat labels
          end
          opts.separator ''
        end
      end

      def execute
        require_repo
        self.action = 'create'

        options.parse! args

        if extract_issue
          Edit.execute args.push('-so', issue, '--', repo)
          exit
        end

        case action
        when 'index'
          if assigns.key? :assignee
            args.unshift assigns[:assignee] if assigns[:assignee]
            args.unshift '-u'
          end
          args.unshift '-w' if web
          List.execute args.push('--', repo)
        when 'create'
          if web
            Web.new(repo).open 'issues/new'
          else
            unless args.empty?
              assigns[:title], assigns[:body] = args.join(' '), assigns[:title]
            end
            assigns[:title] = args.join ' ' unless args.empty?
            if assigns[:title].nil? || editor
              e = Editor.new 'GHI_ISSUE'
              message = e.gets format_editor(assigns)
              e.unlink "There's no issue?" if message.nil? || message.empty?
              assigns[:title], assigns[:body] = message.split(/\n+/, 2)
            end
            i = throb { api.post "/repos/#{repo}/issues", assigns }.body
            e.unlink if e
            puts format_issue(i)
            puts 'Opened.'
          end
        end
      rescue Client::Error => e
        raise unless error = e.errors.first
        abort "%s %s %s %s." % [
          error['resource'],
          error['field'],
          [*error['value']].join(', '),
          error['code']
        ]
      end
    end
  end
end
module GHI
  module Commands
    class Show < Command
      attr_accessor :patch, :web

      def options
        OptionParser.new do |opts|
          opts.banner = 'usage: ghi show <issueno>'
          opts.separator ''
          opts.on('-p', '--patch') { self.patch = true }
          opts.on('-w', '--web') { self.web = true }
        end
      end

      def execute
        require_issue
        require_repo
        options.parse! args
        patch_path = "pull/#{issue}.patch" if patch # URI also in API...
        if web
          Web.new(repo).open patch_path || "issues/#{issue}"
        else
          if patch_path
            i = throb { Web.new(repo).curl patch_path }
            unless i.start_with? 'From'
              warn 'Patch not found'
              abort
            end
            page do
              no_color { puts i }
              break
            end
          else
            i = throb { api.get "/repos/#{repo}/issues/#{issue}" }.body
            page do
              puts format_issue(i)
              n = i['comments']
              if n > 0
                puts "#{n} comment#{'s' unless n == 1}:\n\n"
                Comment.execute %W(-l #{issue} -- #{repo})
              end
              break
            end
          end
        end
      end
    end
  end
end
#!/usr/bin/env ruby
GHI.execute ARGV
