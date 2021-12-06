require "mutex"

# A splay tree is a type of binary search tree that self organizes so that the
# most frequently accessed items tend to be towards the root of the tree, where
# they can be accessed more quickly.

# This implementation provides a hash-like interface, representing a key-value
# mapping, similar to a dictionary. Like a Hash, the primary operations are
# storing a key-value association (`#[]=`), retrieving a value that is associated
# with a given key (`#[]`), and deleting a value from the tree (`#delete()`).
#
# Keys are unique within the tree, so assigning to the same key twice will cause
# the old value to be overwritten by the new value.
#
# This implementation of a Splay Tree also provides a couple features that are not
# typically found in Splay Trees -- efficient removal of the items that are generally
# least frequently accessed (`#prune()`), and an extra fast search option (`#obtain`).
#
# ```
# # Create a new SplayTreeMap with both keys and values typed as Strings.
# stm = SplayTreeMap(String, String).new
#
# # Add some values to the tree.
# stm["this"] = "that"
# stm["something"] = "else"
# stm["junk"] = "pile"
#
# Check for the existence of a key, and print the associated value if it exists.
# if stm.has_key?("this")
#   puts stm["this"]
# end
#
# # Unlike a Hash, attempting to access a key that isn't present simply returns a nil.
#
# puts stm["Gone West"] # => nil
#
# # Remove a key from the tree.
#
# stm.delete("junk")
#
# # Find a value very quickly (particularly if it is near the root of the tree).
#
# entry = stm.obtain("something") # This finds, but doesn't splay.
#
# # Remove the elements of the tree which are likely to be the least accessed elements.
#
# stm.prune # remove all leaves
#
# # SplayTreeMap is (mostly) threadsafe
#
# As of Crystal 1.0.0, a Hash is not thread safe, by default. A SplayTreeMap is.
# ```
#
# This implementation was originally derived from the incomplete and broken implementation
# in the Crystalline shard found at https://github.com/jtomschroeder/crystalline

class SplayTreeMap(K, V)
  include Enumerable({K, V})
  include Iterable({K, V})
  include Comparable(SplayTreeMap)
  VERSION = "0.2.2"

  private class Unk; end

  getter? was_pruned : Bool = false

  @maxsize : UInt64? = nil
  @lock = Mutex.new(protection: Mutex::Protection::Reentrant)
  @root : Node(K, V)? = nil
  @size : Int32 = 0
  @header : Node(K, V) = Node(K, V).new(nil, nil)
  @block : (SplayTreeMap(K, V), K -> V)?
  @on_prune : (K, V ->)?

  # Creates an empty `SplayTreeMap`.
  def initialize
    @block = nil
  end

  # Creates a new empty `SplayTreeMap` with a *block* that is called when a key is
  # missing from the tree.
  #
  # ```
  # stm = SplayTreeMap(String, Array(Int32)).new { |t, k| t[k] = [] of Int32 }
  # stm["a"] << 1
  # stm["a"] << 2
  # stm["a"] << 3
  # puts stm.inspect # => [1,2,3]
  # ```
  def initialize(seed : Enumerable({K, V})? | Iterable({K, V})? = nil, block : (SplayTreeMap(K, V), K -> V)? = nil)
    @block = block
    self.merge!(seed) if seed
  end

  # Creates a new empty `SplayTreeMap` with a *block* that is called when a key is
  # missing from the tree.
  #
  # ```
  # stm = SplayTreeMap(String, Array(Int32)).new { |t, k| t[k] = [] of Int32 }
  # stm["a"] << 1
  # stm["a"] << 2
  # stm["a"] << 3
  # puts stm.inspect # => [1,2,3]
  # ```
  def self.new(seed : Enumerable({K, V})? | Iterable({K, V})? = nil, &block : (SplayTreeMap(K, V), K -> V))
    new(seed: seed, block: block)
  end

  # Creates a new empty `SplayTreeMap` with a default return value for any missing key.
  #
  # ```
  # stm = SplayTreeMap(String, String).new("Unknown")
  # stm["xyzzy"] # => "Unknown"
  # ```
  def self.new(default_value : V)
    new { default_value }
  end

  # Creates a new `SplayTreeMap`, populating it with values from the *Enumerable*
  # or the *Iterable* seed object, and with a default return value for any missing
  # key.
  #
  # ```
  # stm = SplayTreeMap.new({"this" => "that", "something" => "else"}, "Unknown")
  # stm["something"] # => "else"
  # stm["xyzzy"]     # => "Unknown"
  # ```
  def self.new(seed : Enumerable({K, V})? | Iterable({K, V})?, default_value : V)
    new(seed: seed) { default_value }
  end

  def on_prune(&block : K, V ->)
    @on_prune = block
  end

  # Return the current number of key/value pairs in the tree.
  getter size
  getter root

  # Get the maximum size of the tree. If set to nil, the size in unbounded.
  def maxsize
    @maxsize
  end

  # Set the maximum size of the tree. If set to nil, the size is unbounded.
  # If the size is set to a value that is less than the current size, an immediate
  # prune operation will be performed.
  def maxsize=(value)
    @maxsize = value.to_u64

    if mxsz = maxsize
      while @size > mxsz
        @lock.synchronize do
          prune
        end
      end
    end
  end

  # Compares two SplayTreeMaps. All contained objects must also be comparable,
  # or this method will trigger an exception.
  def <=>(other : SplayTreeMap(L, W)) forall L, W
    cmp = surface_cmp(other)
    return cmp unless cmp == 0

    # OK. They are both SplayTreeMaps with the same type signature and the same
    # size. Time to compare them for equality.

    me_iter = each
    other_iter = other.each

    cmp = 0
    @lock.synchronize do
      loop do
        me_entry = me_iter.next?
        other_entry = other_iter.next?
        if me_entry.nil? || other_entry.nil?
          return 0
        else
          cmp = me_entry.as({K, V}) <=> other_entry.as({L, W})
          return cmp unless cmp == 0
        end
      end
    end
  end

  private def surface_cmp(other)
    @lock.synchronize do
      return nil if !other.is_a?(SplayTreeMap) || typeof(self) != typeof(other)

      return -1 if self.size < other.size
      return 1 if self.size > other.size
    end
    0
  end

  # Searches for the given *key* in the tree and returns the associated value.
  # If the key is not in the tree, a KeyError will be raised.
  #
  # ```
  # stm = SplayTreeMap(String, String).new
  # stm["foo"] = "bar"
  # stm["foo"] # => "bar"
  #
  # stm = SplayTreeMap(String, String).new("bar")
  # stm["foo"] # => "bar"
  #
  # stm = SplayTreeMap(String, String).new { "bar" }
  # stm["foo"] # => "bar"
  #
  # stm = Hash(String, String).new
  # stm["foo"] # raises KeyError
  # ```
  def [](key : K)
    (get key).as(V)
  end

  # Returns the value for the key given by *key*.
  # If not found, returns `nil`. This ignores the default value set by `Hash.new`.
  #
  # ```
  # stm = SplayTreeMap(String, String).new
  # stm["foo"]? # => "bar"
  # stm["bar"]? # => nil
  #
  # stm = SplayTreeMap(String, String).new("bar")
  # stm["foo"]? # => nil
  # ```
  def []?(key : K)
    get(key: key, raise_exception: false)
  end

  # :nodoc:
  def get(key : K, raise_exception = true) : V?
    v = get_impl(key)
    if v == Unk
      if (block = @block) && key.is_a?(K)
        block.call(self, key.as(K)).as(V)
      else
        raise_exception ? raise KeyError.new("Missing hash key: #{key.inspect}") : nil
      end
    else
      v.as(V)
    end
  end

  private def get_impl(key : K)
    @lock.synchronize do
      return Unk unless @root

      splay(key)
      if root = @root
        root.key == key ? root.value : Unk
      end
    end
  end

  # Create a key/value association.
  #
  # ```
  # stm["this"] = "that"
  # ```
  def []=(key, value)
    push(key, value)
    value
  end

  # :nodoc:
  def push(key, value)
    # TODO: This is surprisingly slow. I assume it is due to the overhead
    # of declaring nodes on the heap. Is there a way to make them work as
    # structs instead of classes?
    @lock.synchronize do
      unless @root
        @root = Node(K, V).new(key.as(K), value.as(V))
        @size = 1
        return value
      end

      splay(key)

      if root = @root
        cmp = key <=> root.key
        if cmp == 0
          old_value = root.value
          root.value = value
          return old_value
        end
        node = Node(K, V).new(key, value)
        if cmp == -1
          node.left = root.left
          node.right = root
          root.left = nil
        else
          node.right = root.right
          node.left = root
          root.right = nil
        end
      end

      @root = node
      @size += 1

      if mxsz = maxsize
        if @size > mxsz
          prune
        else
          @was_pruned = false
        end
      end
    end

    nil
  end

  # Resets the state of the `SplayTreeMap`, clearing all key/value associations.
  def clear
    @lock.synchronize do
      @was_pruned = false
      @pcount = 0
      @root = nil
      @size = 0
      @header = Node(K, V).new(nil, nil)
    end
  end

  # Returns new `SplayTreeMap` that has all of the `nil` values and their
  # associated keys removed.
  #
  # ```
  # stm = SplayTreeMap.new({"hello" => "world", "foo" => nil})
  # stm.compact # => {"hello" => "world"}
  # ```
  def compact
    @lock.synchronize do
      each_with_object(self.class.new) do |(key, value), memo|
        memo[key] = value unless value.nil?
      end
    end
  end

  # Removes all `nil` values from `self`. Returns `nil` if no changes were made.
  #
  # ```
  # stm = SplayTreeMap.new({"hello" => "world", "foo" => nil})
  # stm.compact! # => {"hello" => "world"}
  # stm.compact! # => nil
  # ```
  def compact!
    reject! { |_key, value| value.nil? }
  end

  # Deletes the key-value pair and returns the value, else yields *key* with given block.
  #
  # ```
  # stm = SplayTreeMap.new({"foo" => "bar"})
  # stm.delete("foo") { |key| "#{key} not found" } # => "bar"
  # stm.fetch("foo", nil)                          # => nil
  # stm.delete("baz") { |key| "#{key} not found" } # => "baz not found"
  # ```
  def delete(key)
    value = delete_impl(key)
    value != Unk ? value : yield key
  end

  # Deletes the key-value pair and returns the value, otherwise returns `nil`.
  #
  # ```
  # stm = SplayTreeMap.new({"foo" => "bar"})
  # stm.delete("foo")     # => "bar"
  # stm.fetch("foo", nil) # => nil
  # ```
  def delete(key)
    delete(key) { nil }
  end

  # :nodoc:
  def delete_impl(key)
    deleted = Unk
    @lock.synchronize do
      splay(key)
      if root = @root
        if key == root.key # The key exists
          deleted = root.value
          if root.left.nil?
            @root = root.right
          else
            x = root.right
            @root = root.left
            new_root = max
            splay(new_root.not_nil!)
            @root.not_nil!.right = x
          end
          @size -= 1
        end
      end
    end
    deleted
  end

  # DEPRECATED: This is just `reject!` by another name. Use that instead.
  # Deletes each key-value pair for which the given block returns `true`.
  # Returns the `SplayTreeMap`.
  #
  # ```
  # stm = SplayTreeMap.new({"foo" => "bar", "fob" => "baz", "bar" => "qux"})
  # stm.delete_if { |key, value| key.starts_with?("fo") }
  # stm # => { "bar" => "qux" }
  # ```
  def delete_if : self
    reject! { |k, v| yield k, v }
    self
  end

  # Traverses the depth of a structure and returns the value, otherwise
  # raises `KeyError`.
  #
  # ```
  # h = {"a" => {"b" => [10, 20, 30]}}
  # stm = SplayTreeMap.new(h)
  # stm.dig "a", "b" # => [10, 20, 30]
  # stm.dig "a", "c" # raises KeyError
  # ```
  def dig(key : K, *subkeys)
    @lock.synchronize do
      if (value = self[key]) && value.responds_to?(:dig)
        return value.dig(*subkeys)
      end
    end
    raise KeyError.new "SplayTreeMap value not diggable for key: #{key.inspect}"
  end

  # :nodoc:
  def dig(key : K)
    self[key]
  end

  # Traverses the depth of a structure and returns the value.
  # Returns `nil` if not found.
  #
  # ```
  # h = {"a" => {"b" => [10, 20, 30]}}
  # stm = SplayTreeMap.new(h)
  # stm.dig "a", "b" # => [10, 20, 30]
  # stm.dig "a", "c" # => nil
  # ```
  def dig?(key : K, *subkeys)
    @lock.synchronize do
      if (value = self[key]?) && value.responds_to?(:dig?)
        return value.dig?(*subkeys)
      end
    end
  end

  # :nodoc:
  def dig?(key : K)
    self[key]?
  end

  # Duplicates a `SplayTreeMap`.
  #
  # ```
  # stm_a = {"foo" => "bar"}
  # stm_b = hash_a.dup
  # stm_b.merge!({"baz" => "qux"})
  # stm_a # => {"foo" => "bar"}
  # ```
  def dup
    @lock.synchronize do
      return SplayTreeMap.new(self)
    end
  end

  # Calls the given block for each key/value pair, passing the pair into the block.
  #
  # ```
  # stm = SplayTreeMap.new({"foo" => "bar"})
  #
  # stm.each do |key, value|
  #   key   # => "foo"
  #   value # => "bar"
  # end
  #
  # stm.each do |key_and_value|
  #   key_and_value # => {"foo", "bar"}
  # end
  # ```
  #
  # The enumeration follows the order the keys were inserted.
  def each(& : {K, V} ->) : Nil
    @lock.synchronize do
      iter = EntryIterator(K, V).new(self)
      while !(entry = iter.next).is_a?(Iterator::Stop)
        yield entry
      end
    end
  end

  # Returns an iterator which can be used to access all of the elements in the tree.
  #
  # ```
  # stm = SplayTreeMap.new({"foo" => "bar", "fob" => "baz", "qix" => "qux"})
  #
  # set = [] of Tuple(String, String)
  # iterator = stm.each
  # while entry = iterator.next
  #   set << entry
  # end
  #
  # set  # => [{"fob" => "baz"}, {"foo" => "bar", "qix" => "qux"}]
  #
  def each : EntryIterator(K, V)
    EntryIterator(K, V).new(self)
  end

  # Calls the given block for each key-value pair and passes in the key.
  #
  # ```
  # stm = SplayTreeMap.new({"foo" => "bar"})
  # stm.each_key do |key|
  #   key # => "foo"
  # end
  # ```
  #
  # The enumeration is in tree order, from smallest to largest.
  def each_key
    each do |key, _value|
      yield key
    end
  end

  # Returns an iterator over the SplayTreeMap keys.
  #
  # ```
  # stm = SplayTreeMap.new({"foo" => "bar", "baz" => "qux"})
  # iterator = stm.each_key
  #
  # key = iterator.next
  # key # => "foo"
  #
  # key = iterator.next
  # key # => "baz"
  # ```
  #
  # The enumeration is in tree order, from smallest to largest.
  def each_key
    KeyIterator(K, V).new(self)
  end

  # Calls the given block for each key-value pair and passes in the value.
  #
  # ```
  # stm = SplayTreeMap.new({"foo" => "bar"})
  # stm.each_value do |value|
  #   value # => "bar"
  # end
  # ```
  #
  # The enumeration is in tree order, from smallest to largest.
  def each_value
    each do |_key, value|
      yield value
    end
  end

  # Returns an iterator over the hash values.
  # Which behaves like an `Iterator` consisting of the value's types.
  #
  # ```
  # stm = SplayTreeMap.new({"foo" => "bar", "baz" => "qux"})
  # iterator = stm.each_value
  #
  # value = iterator.next
  # value # => "bar"
  #
  # value = iterator.next
  # value # => "qux"
  # ```
  #
  # The enumeration is in tree order, from smallest to largest.
  def each_value
    ValueIterator(K, V).new(self)
  end

  # Returns true of the tree contains no key/value pairs.
  #
  # ```
  # stm = SplayTreeMap(Int32, Int32).new
  # stm.empty? # => true
  # stm[1] = 1
  # stm.empty? # => false
  # ```
  #
  def empty?
    @size == 0
  end

  # Returns the value for the key given by *key*, or when not found calls the given block with the key.
  # This ignores the default value set by `SplayTreeMap.new`.
  #
  # ```
  # stm = SplayTreeMap.new({"foo" => "bar"})
  # stm.fetch("foo") { "default value" }  # => "bar"
  # stm.fetch("bar") { "default value" }  # => "default value"
  # stm.fetch("bar") { |key| key.upcase } # => "BAR"
  # ```
  def fetch(key)
    value = get_impl(key)
    value != Unk ? value : yield key
  end

  # Returns the value for the key given by *key*, or when not found the value given by *default*.
  # This ignores the default value set by `SplayTreeMap.new`.
  #
  # ```
  # stm = SplayTreeMap.new({"foo" => "bar"})
  # stm.fetch("foo", "foo") # => "bar"
  # stm.fetch("bar", "foo") # => "foo"
  # ```
  def fetch(key, default)
    fetch(key) { default }
  end

  # Obtain a key without splaying. This is much faster than using `#[]` but the
  # lack of a splay operation means that the accessed value will not move closer
  # to the root of the tree, which bypasses the normal optimization behavior of
  # Splay Trees.
  #
  # A KeyError will be raised if the key can not be found in the tree.
  def obtain(key : K) : V
    v = obtain_impl(key)
    v == Unk ? raise KeyError.new("Missing hash key: #{key.inspect}") : v.as(V)
  end

  private def obtain_impl(key : K)
    @lock.synchronize do
      node = @root
      return Unk if node.nil?

      loop do
        return Unk unless node
        cmp = key <=> node.key
        if cmp == -1
          node = node.left
        elsif cmp == 1
          node = node.right
        else
          return node.value
        end
      end
    end
  end

  # Return a boolean value indicating whether the given key can be found in the tree.
  #
  # ```
  # stm = SplayTreeMap.new({"a" => 1, "b" => 2})
  # stm.has_key?("a") # => true
  # stm.has_key?("c") # => false
  # ```
  #
  def has_key?(key) : Bool
    get_impl(key) == Unk ? false : true
  end

  # Return a boolean value indicating whether the given value can be found in the tree.
  # This is potentially slow as it requires scanning the tree until a match is found or
  # the end of the tree is reached.
  # ```
  # stm = SplayTreeMap.new({"a" => 1, "b" => 2})
  # stm.has_value?("2") # => true
  # stm.has_value?("4") # => false
  # ```
  #
  def has_value?(value) : Bool
    self.each do |_k, v|
      return true if v == value
    end
    false
  end

  # Return the height of the current tree.
  def height
    height_recursive(@root)
  end

  # Return the height at which a given key can be found.
  def height(key) : Int32?
    node = @root
    return nil if node.nil?

    h = 0
    loop do
      return nil unless node
      cmp = key <=> node.key
      if cmp == -1
        h += 1
        node = node.left
      elsif cmp == 1
        h += 1
        node = node.right
      else
        return h
      end
    end
  end

  # Recursively determine height
  private def height_recursive(node : Node?)
    if node
      left_height = 1 + height_recursive(node.left)
      right_height = 1 + height_recursive(node.right)

      left_height > right_height ? left_height : right_height
    else
      0
    end
  end

  # Returns a key with the given *value*, else yields *value* with the given block.
  #
  # ```
  # stm = SplayTreeMap.new({"foo" => "bar"})
  # stm.key_for("bar") { |value| value.upcase } # => "foo"
  # stm.key_for("qux") { |value| value.upcase } # => "QUX"
  # ```
  def key_for(value)
    each do |k, v|
      return k if v == value
    end
    yield value
  end

  # Returns a key with the given *value*, else raises `KeyError`.
  #
  # ```
  # stm = SplayTreeMap.new({"foo" => "bar", "baz" => "qux"})
  # stm.key_for("bar")    # => "foo"
  # stm.key_for("qux")    # => "baz"
  # stm.key_for("foobar") # raises KeyError
  # ```
  def key_for(value)
    key_for(value) { raise KeyError.new "Missing key for value: #{value}" }
  end

  # Returns a key with the given *value*, else `nil`.
  #
  # ```
  # stm = SplayTreeMap.new({"foo" => "bar", "baz" => "qux"})
  # stm.key_for?("bar")    # => "foo"
  # stm.key_for?("qux")    # => "baz"
  # stm.key_for?("foobar") # => nil
  # ```
  def key_for?(value)
    key_for(value) { nil }
  end

  # Returns the last key/value pair in the tree.
  def last
    return nil unless @root

    n = @root
    while n && n.right
      n = n.right
    end

    {n.not_nil!.key, n.not_nil!.value}
  end

  # Returns an array of all keys in the tree.
  #
  # ```
  # stm = SplayTreeMap.new({"foo" => "bar", "baz" => "qux"})
  # stm.keys.should eq ["baz", "foo"]
  # ```
  #
  def keys : Array(K)
    @lock.synchronize do
      a = [] of K
      each { |k, _v| a << k }
      a
    end
  end

  # Returns the largest key in the tree.
  def max
    return nil unless @root

    n = @root
    while n && n.right
      n = n.right
    end

    n.not_nil!.key
  end

  # Adds the contents of *other* to this `SplayTreeMap`.
  #
  # For Array-like structures, which return a single value to the block passed
  # to `#each`, that value will be used for both the key and the value.
  #
  # For Array-like structures, where each array element is a two value Tuple,
  # the first value of the Tuple will be the key, and the second will be the
  # value.
  #
  # For Hash-like structures, which pass a key/value tuple into the `#each`,
  # the key and value will be used for the key and value in the tree entry.
  #
  # If a Tuple is passed into the `#each` that has more or fewer than 2 elements,
  # the key for the tree entry will come from the first element in the Tuple, and
  # the value will come from the last element in the Tuple.
  #
  # ```
  # a = [] of Int32
  # 10.times {|x| a << x}
  # stm = SplayTreeMap(Int32, Int32).new({6 => 0, 11 => 0}).merge!(a)
  # stm[11] # => 0
  # stm[6]  # => 6
  #
  # h = {} of Int32 => Int32
  # 10.times {|x| h[x] = x**2}
  # stm = SplayTreeMap(Int32, Int32).new.merge!(h)
  # stm[6] # => 36
  #
  # stm = SplayTreeMap(Int32, Int32).new.merge!({ {4,16},{5},{7,49,343} })
  # stm[4] # => 16
  # stm[5] # => 5
  # stm[7] # => 343
  #
  def merge!(other : T) forall T
    self.merge!(other) { |_k, _v1, v2| v2 }
  end

  # Adds the contents of *other* to this `SplayTreeMap`.
  #
  # If a key already exists in this tree, the block will yielded to, with three
  # arguments, the key, the value in this tree, and the value in *other*. The
  # return value of the block will be used as the merge value for the key.

  def merge!(other : Enumerable({L, W})) forall L, W
    other.each do |k, v|
      if self.has_key?(k)
        self[k] = yield(k, self[k], v)
      else
        self[k] = v
      end
    end

    self
  end

  def merge!(other : Enumerable(L)) forall L
    other.each do |k|
      if self.has_key?(k)
        self[k] = yield(k, self[k], k)
      else
        self[k] = k
      end
    end

    self
  end

  def merge!(other : Enumerable(Tuple))
    other.each do |*args|
      if args[0].size == 1
        k = v = args[0][0]
      else
        k = args[0][0]
        v = args[0][-1]
      end

      if self.has_key?(k)
        self[k] = yield(k, self[k], v)
      else
        self[k] = v
      end
    end

    self
  end

  # Returns a new `SplayTreeMap` with the keys and values of this tree and *other* combined.
  # A value in *other* takes precedence over the one in this tree. Key types **must** be
  # comparable or this will cause a missing `no overload matches` exception on compilation.
  #
  # ```
  # stm = SplayTreeMap.new({"foo" => "bar"})
  # stm.merge({"baz" => "qux"}) # => {"foo" => "bar", "baz" => "qux"}
  # stm                         # => {"foo" => "bar"}
  # ```
  def merge(other : Enumerable({L, W})) forall L, W
    stm = SplayTreeMap(K | L, V | W).new(self)
    stm.merge! other
    stm
  end

  def merge(other : Enumerable({L, W}), &block : K, V, W -> V | W) forall L, W
    stm = SplayTreeMap(K | L, V | W).new(self)
    stm.merge!(other) { |k, v1, v2| yield k, v1, v2 }
    stm
  end

  def merge(other : Enumerable(L)) forall L
    stm = SplayTreeMap(K | L, V | L).new(self)
    stm.merge! other
    stm
  end

  def merge(other : Enumerable({L}), &block : K, V, W -> V | W) forall L
    stm = SplayTreeMap(K | L, V | L).new(self)
    stm.merge!(other) { |k, v1, v2| yield k, v1, v2 }
    stm
  end

  def merge(other : Enumerable(A({L, W}))) forall A, L, W
    stm = SplayTreeMap(K | L, V | W).new(self)
    stm.merge! other
    stm
  end

  def merge(other : Enumerable(A({L, W})), &block : K, V, W -> V | W) forall A, L, W
    stm = SplayTreeMap(K | L, V | W).new(self)
    stm.merge!(other) { |k, v1, v2| yield k, v1, v2 }
    stm
  end

  # Returns the smallest key in the tree.
  def min
    return nil unless @root

    n = @root
    while n && n.left
      n = n.left
    end

    n.not_nil!.key
  end

  # This will remove all of the leaves at the end of the tree branches.
  # That is, every node that does not have any children. This will tend
  # to remove the least used elements from the tree.
  # This function is expensive, as implemented, as it must walk every
  # node in the tree.
  # TODO: Come up with a more efficient way of getting this same effect.
  def prune
    @was_pruned = false
    return if @root.nil?

    @was_pruned = true
    @pcount = 0
    height_limit = height / 2

    @lock.synchronize do
      descend_from(@root.not_nil!, height_limit)
      splay(@root.not_nil!.key)
    end
  end

  # Sets the value of *key* to the given *value*.
  #
  # If a value already exists for `key`, that (old) value is returned.
  # Otherwise the given block is invoked with *key* and its value is returned.
  #
  # ```
  # stm = SplayTreeMap(Int32, String).new
  # stm.put(1, "one") { "didn't exist" } # => "didn't exist"
  # stm.put(1, "uno") { "didn't exist" } # => "one"
  # stm.put(2, "two") { |key| key.to_s } # => "2"
  # ```
  def put(key : K, value : V)
    old_value = push(key, value)
    old_value || yield key
  end

  # Returns a new `SplayTreeMap` consisting of entries for which the block returns `false`.
  # ```
  # stm = SplayTreeMap.new({"a" => 100, "b" => 200, "c" => 300})
  # stm.reject { |k, v| k > "a" } # => {"a" => 100}
  # stm.reject { |k, v| v < 200 } # => {"b" => 200, "c" => 300}
  # ```
  def reject(&block : K, V -> _)
    @lock.synchronize do
      each_with_object(SplayTreeMap(K, V).new) do |(k, v), memo|
        memo[k] = v unless yield k, v
      end
    end
  end

  # Removes a list of keys out of the tree, returning a new tree.
  #
  # ```
  # h = {"a" => 1, "b" => 2, "c" => 3, "d" => 4}.reject("a", "c")
  # h # => {"b" => 2, "d" => 4}
  # ```
  def reject(keys : Array | Tuple)
    @lock.synchronize do
      stm = dup
      keys.each { |k| stm.delete(k) }
      return stm
    end
  end

  # Returns a new `SplayTreeMap` with the given keys removed.
  #
  # ```
  # {"a" => 1, "b" => 2, "c" => 3, "d" => 4}.reject("a", "c") # => {"b" => 2, "d" => 4}
  # ```
  def reject(*keys)
    reject(keys)
  end

  # Equivalent to `SplayTreeMap#reject`, but modifies the current object rather than
  # returning a new one. Returns `nil` if no changes were made.
  def reject!(&block : K, V -> _)
    @lock.synchronize do
      num_entries = size
      keys_to_delete = [] of K
      each do |key, value|
        keys_to_delete << key if yield(key, value)
      end
      keys_to_delete.each do |key|
        delete(key)
      end
      num_entries == size ? nil : self
    end
  end

  # Removes a list of keys out of the tree.
  #
  # ```
  # h = {"a" => 1, "b" => 2, "c" => 3, "d" => 4}.reject!("a", "c")
  # h # => {"b" => 2, "d" => 4}
  # ```
  def reject!(keys : Array | Tuple)
    @lock.synchronize do
      keys.each { |k| delete(k) }
    end
    self
  end

  # Removes the given keys from the tree.
  #
  # ```
  # {"a" => 1, "b" => 2, "c" => 3, "d" => 4}.reject!("a", "c") # => {"b" => 2, "d" => 4}
  # ```
  def reject!(*keys)
    reject!(keys)
  end

  # Returns a new hash consisting of entries for which the block returns `true`.
  # ```
  # h = {"a" => 100, "b" => 200, "c" => 300}
  # h.select { |k, v| k > "a" } # => {"b" => 200, "c" => 300}
  # h.select { |k, v| v < 200 } # => {"a" => 100}
  # ```
  def select(&block : K, V -> _)
    reject { |k, v| !yield(k, v) }
  end

  # Returns a new `SplayTreeMap` with the given keys.
  #
  # ```
  # SplayTreeMap.new({"a" => 1, "b" => 2, "c" => 3, "d" => 4}).select({"a", "c"}) # => {"a" => 1, "c" => 3}
  # SplayTreeMap.new({"a" => 1, "b" => 2, "c" => 3, "d" => 4}).select("a", "c")   # => {"a" => 1, "c" => 3}
  # SplayTreeMap.new({"a" => 1, "b" => 2, "c" => 3, "d" => 4}).select(["a", "c"]) # => {"a" => 1, "c" => 3}
  # ```
  def select(keys : Array | Tuple)
    stm = SplayTreeMap(K, V).new
    @lock.synchronize do
      keys.each { |k| k = k.as(K); stm[k] = obtain(k) if has_key?(k) }
    end
    stm
  end

  # :ditto:
  def select(*keys)
    self.select(keys)
  end

  # Equivalent to `Hash#select` but makes modification on the current object rather that returning a new one. Returns `nil` if no changes were made
  def select!(&block : K, V -> _)
    reject! { |k, v| !yield(k, v) }
  end

  # Removes every element except the given ones.
  #
  # ```
  # h1 = {"a" => 1, "b" => 2, "c" => 3, "d" => 4}.select!({"a", "c"})
  # h2 = {"a" => 1, "b" => 2, "c" => 3, "d" => 4}.select!("a", "c")
  # h3 = {"a" => 1, "b" => 2, "c" => 3, "d" => 4}.select!(["a", "c"])
  # h1 == h2 == h3 # => true
  # h1             # => {"a" => 1, "c" => 3}
  # ```
  def select!(keys : Array | Tuple)
    each { |k, _v| delete(k) unless keys.includes?(k) }
    self
  end

  # :ditto:
  def select!(*keys)
    select!(keys)
  end

  # Transform the `SplayTreeMap` into an `Array(Tuple(K, V))`.
  #
  # ```
  # stm = SplayTreeMap.new({"foo" => "bar", "baz" => "qux"})
  # ary = stm.to_a # => [{"baz", "qux"}, {"foo", "bar"}]
  # stm2 = SplayTreeMap.new(ary)
  # stm == stm2 # => true
  # ```
  def to_a
    a = Array({K, V}).new
    each { |k, v| a << {k, v} }
    a
  end

  # Transform a `SplayTreeMap(K,V)` into a `Hash(K,V)`.
  #
  # ```
  # stm = SplayTreeMap.new({"foo" => "bar", "baz" => "qux"})
  # h = stm.to_h # => {"baz" => "qux", "foo" => "bar"}
  # ```
  def to_h
    h = Hash(K, V).new
    each { |k, v| h[k] = v }
    h
  end

  # Transform the `SplayTreeMap` into a `String` representation.
  def to_s(io : IO) : Nil
    final = self.size
    count = 0
    io << String.build do |buff|
      buff << "{ "
      self.each do |k, v|
        count += 1
        buff << k.inspect
        buff << " => "
        buff << v.inspect
        buff << ", " if count < final
      end
      buff << " }"
    end
  end

  # Returns a new `SplayTreeMap` with all of the key/value pairs converted using
  # the provided block. The block can change the types of both keys and values.
  #
  # ```
  # stm = SplayTreeMap({1 => 1, 2 => 4, 3 => 9, 4 => 16})
  # stm = stm.transform {|k, v| {k.to_s, v.to_s}}
  # stm  # => {"1" => "1", "2" => "4", "3" => "9", "4" => "16"}
  # ```
  #
  def transform(&block : {K, V} -> {K2, V2}) forall K2, V2
    each_with_object(SplayTreeMap(K2, V2).new) do |(key, value), memo|
      key2, value2 = yield({key, value})
      memo[key2] = value2
    end
  end

  # Returns a new `SplayTreeMap` with all keys converted using the block operation.
  # The block can change a type of keys.
  #
  # ```
  # stm = SplayTreeMap.new({:a => 1, :b => 2, :c => 3})
  # stm.transform_keys { |key| key.to_s } # => {"a" => 1, "b" => 2, "c" => 3}
  # ```
  def transform_keys(&block : K -> K2) forall K2
    each_with_object(SplayTreeMap(K2, V).new) do |(key, value), memo|
      memo[yield(key)] = value
    end
  end

  # Returns a new SplayTreeMap with all values converted using the block operation.
  # The block can change a type of values.
  #
  # ```
  # stm = SplayTreeMap.new({:a => 1, :b => 2, :c => 3})
  # stm.transform_values { |value| value + 1 } # => {:a => 2, :b => 3, :c => 4}
  # ```
  def transform_values(&block : V -> V2) forall V2
    each_with_object(SplayTreeMap(K, V2).new) do |(key, value), memo|
      memo[key] = yield(value)
    end
  end

  # Modifies the values of the current `SplayTreeMap` according to the provided block.
  #
  # ```
  # stm = SplayTreeMap.new({:a => 1, :b => 2, :c => 3})
  # stm.transform_values! { |value| value + 1 } # => {:a => 2, :b => 3, :c => 4}
  # ```
  def transform_values!(&block : V -> V)
    each do |key, value|
      memo[key] = yield(value)
    end
    self
  end

  # Returns an array containing all of the values in the tree. The array is in
  # the order of the associated keys.
  #
  # ```
  # stm = SplayTreeMap.new({"a" => 1, "b" => 2, "c" => 3, "d" => 4})
  # stm.values # => [1, 2, 3, 4]
  # ```
  #
  def values : Array(V)
    a = [] of V
    each { |_k, v| a << v }
    a
  end

  # Returns a tuple populated with the values associated with the given *keys*.
  # Raises a KeyError if any key is invalid.
  #
  # ```
  # stm = SplayTreeMap.new({"a" => 1, "b" => 2, "c" => 3, "d" => 4})
  # stm.values_at("a", "c")      # => {1, 3}
  # stm.values_at("a", "d", "e") # => KeyError
  # ```
  def values_at(*indexes : K)
    indexes.map { |index| self[index] }
  end

  # Returns a tuple populated with the values associated with the given *keys*.
  # Returns `nil` for any key that is invalid.
  #
  # ```
  # stm = SplayTreeMap.new({"a" => 1, "b" => 2, "c" => 3, "d" => 4})
  # stm.values_at?("a", "c")      # => {1, 3}
  # stm.values_at?("a", "d", "e") # => {1, 4, nil}
  # ```
  def values_at?(*indexes : K)
    indexes.map { |index| self[index]? }
  end

  # Zips two arrays into a `SplayTreeMap`, taking keys from *ary1* and values from *ary2*.
  #
  # ```
  # SplayTreeMap.zip(["key1", "key2", "key3"], ["value1", "value2", "value3"])
  # # => {"key1" => "value1", "key2" => "value2", "key3" => "value3"}
  # ```
  def self.zip(ary1 : Array(K), ary2 : Array(V))
    stm = SplayTreeMap(K, V).new
    ary1.each_with_index do |key, i|
      stm[key] = ary2[i]
    end
    stm
  end

  # This will recursively walk the whole tree, calling the given block for each node.
  private def each_descend_from(node, &blk : K, V ->)
    return if node.nil?

    each_descend_from(node.left, &blk) if !node.left.nil?
    yield(node.key, node.value)
    each_descend_from(node.right, &blk) if !node.right.nil?
  end

  private def descend_from(node, height_limit, current_height = 0)
    return if node.nil?
    current_height += 1

    n = node.left
    if n && !n.terminal?
      descend_from(n, height_limit, current_height)
    else
      prune_from(node) if current_height > height_limit
    end

    descend_from(node.right, height_limit, current_height) if node.right
  end

  private def prune_from(node)
    return if node.nil?
    n = node.left
    if n && n.terminal?
      if @on_prune && (blk = @on_prune)
        blk.call(n.key, n.value)
      end
      node.left = nil
      @size -= 1
    end

    n = node.right
    if n && n.terminal?
      if @on_prune && (blk = @on_prune)
        blk.call(n.key, n.value)
      end
      node.right = nil
      @size -= 1
    end
  end

  # Moves key to the root, updating the structure in each step.
  private def splay(key : K)
    return nil if key.nil?

    l, r = @header, @header
    t = @root
    @header.left, @header.right = nil, nil

    loop do
      if t
        if (key <=> t.key) == -1
          tl = t.left
          break unless tl
          if (key <=> tl.key) == -1
            y = tl
            t.left = y.right
            y.right = t
            t = y
            break unless t.left
          end
          r.left = t
          r = t
          t = t.left
        elsif (key <=> t.key) == 1
          tr = t.right
          break unless tr
          if (key <=> tr.key) == 1
            y = tr
            t.right = y.left
            y.left = t
            t = y
            break unless t.right
          end
          l.right = t
          l = t
          t = t.right
        else
          break
        end
      else
        break
      end
    end

    if t
      l.right, r.left = t.left, t.right
      t.left, t.right = @header.right, @header.left
      @root = t
    end
  end

  private module BaseIterator
    def initialize(@tree)
      pull_lefts_from @tree.root
    end

    def base_next
      return stop if @stack.empty?

      next_node_to_return = @stack.pop
      next_node_to_return_right = next_node_to_return.right
      if !next_node_to_return_right.nil?
        pull_lefts_from next_node_to_return_right
      end

      yield next_node_to_return
    end

    def pull_lefts_from(node)
      return if node.nil?

      node_left = node.left
      while !node_left.nil?
        @stack << node
        node = node_left
        node_left = node.left
      end
      @stack << node
    end
  end

  private class EntryIterator(K, V)
    include BaseIterator
    include Iterator({K, V})

    @stack : Array(Node(K, V)) = [] of Node(K, V)
    @tree : SplayTreeMap(K, V)
    @node : Node(K, V)?

    def next
      base_next { |entry| {entry.key, entry.value} }
    end

    def next? : {K, V}?
      retval = base_next { |entry| {entry.key, entry.value} }
      retval.is_a?(Iterator::Stop) ? nil : retval
    end
  end

  private class KeyIterator(K, V)
    include BaseIterator
    include Iterator({K, V})

    @stack : Array(Node(K, V)) = [] of Node(K, V)
    @tree : SplayTreeMap(K, V)
    @node : Node(K, V)?

    def next
      base_next &.key
    end
  end

  private class ValueIterator(K, V)
    include BaseIterator
    include Iterator({K, V})

    @stack : Array(Node(K, V)) = [] of Node(K, V)
    @tree : SplayTreeMap(K, V)
    @node : Node(K, V)?

    def next
      base_next &.value
    end
  end

  private class Node(K, V)
    include Comparable(Node(K, V))
    property left : Node(K, V)?
    property right : Node(K, V)?

    def initialize(@key : K?, @value : V?, @left = nil, @right = nil)
    end

    def terminal?
      left.nil? && right.nil?
    end

    # Enforce type of node properties (key & value)
    macro node_prop(prop, type)
      def {{prop}}; @{{prop}}.as({{type}}); end
      def {{prop}}=(@{{prop}} : {{type}}); end
    end

    node_prop key, K
    node_prop value, V

    def <=>(other : Node(K, V))
      cmp = key <=> other.key
      return cmp unless cmp == 0
      value <=> other.value
    end
  end
end
