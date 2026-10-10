### Item 1
File: lib/hashie/extensions/indifferent_access.rb, line 180
Original:
        other.is_a?(::Hash) &&
          !(other.respond_to?(:indifferent_access?) &&
            other.indifferent_access?)
Mutated:
        other.is_a?(::Hash)
Context:
 173           super(*string_keys)
 174         end
 175       end
 176 
 177       protected
 178 
 179       def hash_lacking_indifference?(other)
 180         other.is_a?(::Hash) &&
 181           !(other.respond_to?(:indifferent_access?) &&
 182             other.indifferent_access?)
 183       end
 184 
 185       def hash_with_indifference?(other)
 186         other.is_a?(::Hash) &&

### Item 2
File: lib/hashie/extensions/indifferent_access.rb, line 136
Original:
        (keys - other_hash.keys).each { |key| delete(key) }
Mutated:
        (keys + other_hash.keys).each { |key| delete(key) }
Context:
 129       end
 130 
 131       def indifferent_access?
 132         true
 133       end
 134 
 135       def indifferent_replace(other_hash)
 136         (keys - other_hash.keys).each { |key| delete(key) }
 137         other_hash.each { |key, value| self[key] = value }
 138         self
 139       end
 140 
 141       def merge(*args)
 142         result = super

### Item 3
File: lib/hashie/rash.rb, line 139
Original:
      @regexes = @regexes.sort_by { |regex| -@regex_counts[regex] }
Mutated:
      nil
Context:
 132       @hash.respond_to?(method_name)
 133     end
 134 
 135     private
 136 
 137     def optimize_if_necessary!
 138       return unless (@lookups += 1) >= @optimize_every
 139       @regexes = @regexes.sort_by { |regex| -@regex_counts[regex] }
 140       @lookups = 0
 141     end
 142   end
 143 end
 144 

### Item 4
File: lib/hashie/clash.rb, line 57
Original:
        val = self.class.new(self[key]).merge(val) if self[key].is_a?(::Hash) && val.is_a?(::Hash)
Mutated:
        val = self.class.new(self[key]).merge(val) if self[key].is_a?(::Hash)
Context:
  50       method_missing(:id, *args)
  51     end
  52 
  53     def merge_store(key, *args) #:nodoc:
  54       case args.length
  55       when 1
  56         val = args.first
  57         val = self.class.new(self[key]).merge(val) if self[key].is_a?(::Hash) && val.is_a?(::Hash)
  58       else
  59         val = args
  60       end
  61 
  62       self[key.to_sym] = val
  63       self

### Item 5
File: lib/hashie/extensions/symbolize_keys.rb, line 51
Original:
          hash
Mutated:
          nil
Context:
  44         #   test # => {:abc => 'def'}
  45         def symbolize_keys!(hash)
  46           hash.extend(Hashie::Extensions::SymbolizeKeys) unless hash.respond_to?(:symbolize_keys!)
  47           hash.keys.each do |k| # rubocop:disable Performance/HashEachMethods
  48             symbolize_keys_recursively!(hash[k])
  49             hash[convert_key(k)] = hash.delete(k)
  50           end
  51           hash
  52         end
  53 
  54         # Return a copy of hash with all keys converted
  55         # to symbols.
  56         # @param [::Hash] hash
  57         def symbolize_keys(hash)

### Item 6
File: lib/hashie/dash.rb, line 170
Original:
        next unless fetch(prop, nil).nil?
Mutated:
        nil
Context:
 163     end
 164     alias to_hash to_h
 165 
 166     def update_attributes!(attributes)
 167       update_attributes(attributes)
 168 
 169       self.class.defaults.each_pair do |prop, value|
 170         next unless fetch(prop, nil).nil?
 171         self[prop] = begin
 172           val = value.dup
 173           if val.is_a?(Proc)
 174             val.arity == 1 ? val.call(self) : val.call
 175           else
 176             val

### Item 7
File: lib/hashie/rash.rb, line 98
Original:
        optimize_if_necessary!
Mutated:
        nil
Context:
  91       if @hash.include? query
  92         yield @hash[query]
  93         return
  94       end
  95 
  96       case query
  97       when String
  98         optimize_if_necessary!
  99 
 100         # see if any of the regexps match the string
 101         @regexes.each do |regex|
 102           match = regex.match(query)
 103           next unless match
 104           @regex_counts[regex] += 1

### Item 8
File: lib/hashie/extensions/mash/define_accessors.rb, line 39
Original:
              if key? method_name
Mutated:
              if false
Context:
  32               end
  33               send(method_name, *args, &block)
  34             end
  35           end
  36 
  37           def define_reader(key, method_name)
  38             define_method(method_name) do |&block|
  39               if key? method_name
  40                 self.[](method_name, &block)
  41               else
  42                 self.[](key, &block)
  43               end
  44             end
  45           end

### Item 9
File: lib/hashie/mash.rb, line 366
Original:
        [method_name[0..-1], nil]
Mutated:
        [method_name[(-1)..-1], nil]
Context:
 359     protected
 360 
 361     def method_name_and_suffix(method_name)
 362       method_name = method_name.to_s
 363       if method_name.end_with?(*ALLOWED_SUFFIXES)
 364         [method_name[0..-2], method_name[-1]]
 365       else
 366         [method_name[0..-1], nil]
 367       end
 368     end
 369 
 370     def method_suffix(method_name)
 371       method_name = method_name.to_s
 372       method_name[-1] if method_name.end_with?(*ALLOWED_SUFFIXES)

### Item 10
File: lib/hashie/extensions/mash/define_accessors.rb, line 48
Original:
            define_method(method_name) do |value = nil|
Mutated:
            define_method(method_name) do |value = true|
Context:
  41               else
  42                 self.[](key, &block)
  43               end
  44             end
  45           end
  46 
  47           def define_writer(key, method_name)
  48             define_method(method_name) do |value = nil|
  49               if key? method_name
  50                 self.[](method_name, &proc)
  51               else
  52                 assign_property(key, value)
  53               end
  54             end

### Item 11
File: lib/hashie/rash.rb, line 31
Original:
      @optimize_every = 500
Mutated:
      @optimize_every = 501
Context:
  24     attr_accessor :optimize_every
  25 
  26     def initialize(initial = {})
  27       @hash           = {}
  28       @regexes        = []
  29       @ranges         = []
  30       @regex_counts   = Hash.new(0)
  31       @optimize_every = 500
  32       @lookups        = 0
  33 
  34       update(initial)
  35     end
  36 
  37     def update(other)

### Item 12
File: lib/hashie/extensions/method_access.rb, line 32
Original:
        super
Mutated:
        nil
Context:
  25     #   user[:birthday] = nil
  26     #   user.birthday # => nil
  27     #
  28     #   user.not_declared # => NoMethodError
  29     module MethodReader
  30       def respond_to_missing?(name, include_private = false)
  31         return true if key?(name.to_s) || key?(name.to_sym)
  32         super
  33       end
  34 
  35       def method_missing(name, *args)
  36         if key?(name)
  37           self[name]
  38         else

### Item 13
File: lib/hashie/extensions/dash/property_translation.rb, line 107
Original:
                  if property_translations.size > 1
Mutated:
                  if property_translations.size != 1
Context:
 100             translations_hash.key? name
 101           end
 102 
 103           def translations
 104             @translations ||= {}.tap do |translations|
 105               translations_hash.each do |(property_name, property_translations)|
 106                 translations[property_name] =
 107                   if property_translations.size > 1
 108                     property_translations.keys
 109                   else
 110                     property_translations.keys.first
 111                   end
 112               end
 113             end

### Item 14
File: lib/hashie/extensions/dash/property_translation.rb, line 184
Original:
            fail_no_property_error!(property) unless self.class.property?(property)
Mutated:
            nil
Context:
 177               end
 178             end
 179             super attributes_copy
 180           end
 181 
 182           # Raises an NoMethodError if the property doesn't exist
 183           def property_exists?(property)
 184             fail_no_property_error!(property) unless self.class.property?(property)
 185             true
 186           end
 187 
 188           private
 189 
 190           def __translations

### Item 15
File: lib/hashie/extensions/deep_locate.rb, line 99
Original:
          key = nil
Mutated:
          key = true
Context:
  92       end
  93       private_class_method :_deep_locate
  94 
  95       def self._match_comparator?(value, comparator, object)
  96         if object.is_a?(::Hash)
  97           key, value = value
  98         else
  99           key = nil
 100         end
 101 
 102         comparator.call(key, value, object)
 103       end
 104       private_class_method :_match_comparator?
 105 

### Item 16
File: lib/hashie/rash.rb, line 138
Original:
      return unless (@lookups += 1) >= @optimize_every
Mutated:
      return unless (@lookups += 1) > @optimize_every
Context:
 131     def respond_to_missing?(method_name, _include_private = false)
 132       @hash.respond_to?(method_name)
 133     end
 134 
 135     private
 136 
 137     def optimize_if_necessary!
 138       return unless (@lookups += 1) >= @optimize_every
 139       @regexes = @regexes.sort_by { |regex| -@regex_counts[regex] }
 140       @lookups = 0
 141     end
 142   end
 143 end
 144 

### Item 17
File: lib/hashie/extensions/dash/property_translation.rb, line 135
Original:
                self[name] = with.respond_to?(:call) ? with.call(val) : val
Mutated:
                self[name] = false ? with.call(val) : val
Context:
 128           def define_translation(from, property_name, translator)
 129             translations_hash[from][property_name] = translator
 130           end
 131 
 132           def define_writer_for_source_property(property)
 133             define_method "#{property}=" do |val|
 134               __translations[property].each do |name, with|
 135                 self[name] = with.respond_to?(:call) ? with.call(val) : val
 136               end
 137             end
 138           end
 139 
 140           def fail_self_transformation_error!(property_name)
 141             raise ArgumentError,

### Item 18
File: lib/hashie/extensions/mash/permissive_respond_to.rb, line 56
Original:
            !(regular_key?(method_key) || regular_key?(method_key.to_s))
Mutated:
            !(regular_key?(method_key) && regular_key?(method_key.to_s))
Context:
  49         # Override the Mash logging behavior to account for permissiveness
  50         #
  51         # @api private
  52         # @private
  53         def log_collision?(method_key)
  54           self.class.method_cache.include?(method_key) &&
  55             !self.class.disable_warnings?(method_key) &&
  56             !(regular_key?(method_key) || regular_key?(method_key.to_s))
  57         end
  58       end
  59     end
  60   end
  61 end
  62 

### Item 19
File: lib/hashie/extensions/key_conflict_warning.rb, line 50
Original:
        super
Mutated:
        nil
Context:
  43       end
  44 
  45       # Inheritance hook that sets class configuration when inherited.
  46       #
  47       # @api semipublic
  48       # @return [void]
  49       def inherited(subclass)
  50         super
  51         subclass.disable_warnings(disabled_warnings) if disable_warnings?
  52       end
  53     end
  54   end
  55 end
  56 

### Item 20
File: lib/hashie/extensions/pretty_inspect.rb, line 10
Original:
        ret = "#<#{self.class}"
        keys.sort_by(&:to_s).each do |key|
          ret << " #{key}=#{self[key].inspect}"
        end
        ret << '>'
        ret
Mutated:
        raise
Context:
   3     module PrettyInspect
   4       def self.included(base)
   5         base.send :alias_method, :hash_inspect, :inspect
   6         base.send :alias_method, :inspect, :hashie_inspect
   7       end
   8 
   9       def hashie_inspect
  10         ret = "#<#{self.class}"
  11         keys.sort_by(&:to_s).each do |key|
  12           ret << " #{key}=#{self[key].inspect}"
  13         end
  14         ret << '>'
  15         ret
  16       end
