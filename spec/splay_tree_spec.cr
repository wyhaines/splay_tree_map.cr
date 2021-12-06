require "./spec_helper"

describe SplayTreeMap do
  it "creates a Splay Tree with the specified typing" do
    st = SplayTreeMap(String, String).new
    st.class.should eq SplayTreeMap(String, String)
  end

  it "can create trees with complex keys" do
    st = SplayTreeMap({String, String}, String).new
    10.times { |n| st[{n.to_s, n.to_s}] = n.to_s }

    st.size.should eq 10
    st[{"5", "5"}].should eq "5"
  end

  it "can create a tree with a default return value for a missing key" do
    st = SplayTreeMap(String, String).new("XYZZY")
    st["a"] = "a"

    st["a"].should eq "a"
    st["b"].should eq "XYZZY"
    st.has_key?("a").should be_true
    st.has_key?("b").should be_false
    st.has_key?("c").should be_false
  end

  it "can create a tree with a block to initialize missing values" do
    st = SplayTreeMap(String, Array(Int32)).new { |t, k| t[k] = [] of Int32 }
    st["a"] << 1
    st["a"] << 2
    st["a"] << 3
    st["a"].should eq [1, 2, 3]
  end

  it "can create a tree using a hash as a seed" do
    h = Hash(Int32, Int32).new
    10.times { |x| h[x] = x**2 }
    stm = SplayTreeMap.new(h)
    stm.size.should eq 10
    stm[5].should eq 25
  end

  it "inserts 1000 randomly generated unique values and can look them up" do
    ins = {} of Int32 => Int32
    st = SplayTreeMap(Int32, Int32).new
    1000.times do
      loop do
        x = rand(10000000)
        if !ins.has_key?(x)
          ins[x] = x
          st[x] = x
          break
        end
      end
    end

    st.size.should eq 1000

    found = 0
    ins.keys.shuffle!.each { |k| found += 1 if st.has_key?(k) }
    found.should eq 1000

    found = 0
    ins.keys.shuffle!.each { |k| found += 1 if st[k] == ins[k] }
    found.should eq 1000
  end

  it "can find things without splaying to them" do
    ins = {} of Int32 => Int32
    st = SplayTreeMap(Int32, Int32).new
    1000.times do
      loop do
        x = rand(10000000)
        if !ins.has_key?(x)
          ins[x] = x
          st[x] = x
          break
        end
      end
    end

    found = 0
    ins.keys.shuffle!.each { |k| found += 1 if st.obtain(k) == ins[k] }
    found.should eq 1000
  end

  it "tends to move the most accessed things to the top of the tree" do
    ins = {} of Int32 => Int32
    st = SplayTreeMap(Int32, Int32).new
    100000.times do
      loop do
        x = rand(10000000)
        if !ins.has_key?(x)
          ins[x] = x
          st[x] = x
          break
        end
      end
    end

    random_300 = ins.keys.shuffle![0..299]
    top_100 = random_300[0..99]
    intermediate_100 = random_300[100..199]
    regular_100 = random_300[200..299]

    1000.times do
      100.times { st[intermediate_100.sample(1).first] }
      1000.times { st[top_100.sample(1).first] }
    end

    top_heights = [] of Int32
    intermediate_heights = [] of Int32
    regular_heights = [] of Int32

    top_100.each { |x| top_heights << st.height(x).not_nil! }
    intermediate_100.each { |x| intermediate_heights << st.height(x).not_nil! }
    regular_100.each { |x| regular_heights << st.height(x).not_nil! }

    sum_top_100 = top_heights.reduce(0) { |a, v| a + v }
    sum_intermediate_100 = intermediate_heights.reduce(0) { |a, v| a + v }
    sum_regular_100 = regular_heights.reduce(0) { |a, v| a + v }

    Log.debug { "average height -- top :: intermediate :: other == #{sum_top_100 / 100} :: #{sum_intermediate_100 / 100} :: #{sum_regular_100 / 100}" }
    sum_top_100.should be < sum_intermediate_100
    sum_intermediate_100.should be < sum_regular_100
  end

  it "<=>; Can compare SplayTreeMaps" do
    stm_1 = SplayTreeMap.new({"foo" => "bar", "baz" => "qux"})
    stm_2 = SplayTreeMap.new({"foo" => "bar", "baz" => "qux", "bing" => "bang"})
    stm_3 = SplayTreeMap.new({"foo" => "bar", "baz" => "qix"})
    stm_4 = SplayTreeMap.new({"fob" => "bar", "baz" => "qux"})

    (stm_1 == stm_2).should be_false
    (stm_1 < stm_2).should be_true
    (stm_1 < stm_3).should be_false
    (stm_1 < stm_4).should be_false
  end

  it "[]?; can retrive values while returning nil if they are missing" do
    st = SplayTreeMap(Int32, Int32).new
    10.times { |x| st[x] = x }
    st[3]?.should eq 3
    st[11]?.should be_nil
  end

  it "compact; can get a new tree with all nils removed" do
    stm = SplayTreeMap.new({"hello" => "world", "foo" => nil})
    res = stm.compact
    res.size.should eq 1
    res["foo"]?.should eq nil
    res["hello"]?.should eq "world"
  end

  it "compact!; can remove all nils from this tree" do
    stm = SplayTreeMap.new({"hello" => "world", "foo" => nil})
    stm.compact!
    stm["foo"]?.should eq nil
    stm["hello"]?.should eq "world"
    stm.compact!.should be_nil
  end

  it "delete; can delete an individual element" do
    stm = SplayTreeMap.new({"foo" => "bar"})
    (stm.delete("foo") { |key| "#{key} not found" }).should eq "bar"
    stm.fetch("foo", nil).should be_nil
    (stm.delete("baz") { |key| "#{key} not found" }).should eq "baz not found"

    stm = SplayTreeMap.new({"foo" => "bar"})
    stm.delete("foo").should eq "bar"
    stm.fetch("foo", nil).should be_nil
  end

  it "delete_if; can delete records if block is true" do
    stm = SplayTreeMap.new({"foo" => "bar", "fob" => "baz", "bar" => "qux"})
    stm.delete_if { |key, _value| key.starts_with?("fo") }
    stm.size.should eq 1
    stm["bar"].should eq "qux"
    stm["foo"]?.should be_nil
  end

  it "dig; can dig for a nested value, raising on missing" do
    h = {"a" => {"b" => [10, 20, 30]}}
    stm = SplayTreeMap.new(h)
    stm.dig("a", "b").should eq [10, 20, 30]
    expect_raises(KeyError) do
      stm.dig("a", "c")
    end
  end

  it "dig; can dig for a nested value, returning nil on missing" do
    h = {"a" => {"b" => [10, 20, 30]}}
    stm = SplayTreeMap.new(h)
    stm.dig?("a", "b").should eq [10, 20, 30]
    stm.dig?("a", "c").should be_nil
  end

  it "dup; can duplicate a SplayTreeMap" do
    stm_a = {"foo" => "bar"}
    stm_b = stm_a.dup
    stm_b.merge!({"baz" => "qux"})
    stm_a # => {"foo" => "bar"}
  end

  it "each; when called with a block, calls the block for each key/value pair" do
    stm = SplayTreeMap.new({"foo" => "bar"})
    stm.each do |key, value|
      key.should eq "foo"
      value.should eq "bar"
    end

    stm.each do |key_and_value|
      key_and_value.should eq ({"foo", "bar"})
    end

    stm = SplayTreeMap(Int32, Int32).new
    log = [] of Int32
    10.times { |x| stm[x] = x; log << x }

    log.size.should eq 10

    n = 0
    stm.each do |k, _v|
      n += 1
      log.delete(k)
    end

    n.should eq 10
    log.size.should eq 0
  end

  it "each; when called with no arguments, returns an iterator which can be used to walk the tree" do
    stm = SplayTreeMap.new({"foo" => "bar", "fob" => "baz", "qix" => "qux"})

    set = [] of Tuple(String, String)
    iterator = stm.each
    while entry = iterator.next
      break if entry.class == Iterator::Stop
      set << entry.as(Tuple(String, String))
    end

    set.should eq [{"fob", "baz"}, {"foo", "bar"}, {"qix", "qux"}]
  end

  it "each_key; calls the given block for each key-value pair and passes the key" do
    stm = SplayTreeMap.new({"foo" => "bar", "biz" => "baz"})
    set = [] of String
    stm.each_key do |key|
      set << key
    end
    set.should eq ["biz", "foo"]
  end

  it "each_key; returns an iterator over the tree keys" do
    stm = SplayTreeMap.new({"foo" => "bar", "baz" => "qux"})
    iterator = stm.each_key

    key = iterator.next
    key.should eq "baz"

    key = iterator.next
    key.should eq "foo"
  end

  it "each_value; calls the given block for each key-value pair and passes the value" do
    stm = SplayTreeMap.new({"foo" => "bar", "biz" => "baz"})
    set = [] of String
    stm.each_value do |value|
      set << value
    end
    set.should eq ["baz", "bar"]
  end

  it "each_value; returns an iterator over the tree values" do
    stm = SplayTreeMap.new({"foo" => "bar", "baz" => "qux"})
    iterator = stm.each_value

    value = iterator.next
    value.should eq "qux"

    value = iterator.next
    value.should eq "bar"
  end

  it "empty?; returns true if the tree is empty" do
    stm = SplayTreeMap(Int32, Int32).new
    stm.empty?.should be_true
    stm[1] = 1
    stm.empty?.should be_false
  end

  it "fetch; can retrieve a value, ignoring any default from #new" do
    stm = SplayTreeMap.new({"foo" => "bar"}, "xyzzy")
    stm["kleine"].should eq "xyzzy"
    stm.fetch("foo") { "default value" }.should eq "bar"
    stm.fetch("bar") { "default value" }.should eq "default value"
    stm.fetch("bar", &.upcase).should eq "BAR"
    stm.fetch("foo", "foo").should eq "bar"
    stm.fetch("bar", "foo").should eq "foo"
  end

  it "first; can find the first (smallest) key" do
    st = SplayTreeMap(Int32, Int32).new
    10.times { |x| st[x] = x }

    st.first.should eq ({0, 0})
  end

  it "merge!; can merge key/value pairs from another structure that responds to #each" do
    a = [] of Int32
    h = {} of Int32 => Int32
    10.times do |x|
      a << x
      h[x] = x * x
    end

    st_a = SplayTreeMap(Int32, Int32).new({6 => 0, 11 => 0}).merge!(a)
    st_h = SplayTreeMap(Int32, Int32).new.merge!(h)
    st_c = SplayTreeMap(Int32, Int32).new.merge!([{0, 0}, {1, 1}, {2, 4}, {3, 9}, {4, 16}, {5}, {6, 36}, {7, 49, 343}])
    _st_d = SplayTreeMap(Int32, Int32).new.merge!({ {0, 0}, {1, 1}, {2, 4}, {3, 9}, {4, 16}, {5}, {6, 36}, {7, 49, 343} })
    st_a.size.should eq 11
    st_h.size.should eq 10
    st_c.size.should eq 8
    st_a[5].should eq 5
    st_a[6].should eq 6
    st_a[11].should eq 0
    st_h[5].should eq 25
    st_c[5].should eq 5
    st_c[6].should eq 36
    st_c[7].should eq 343
  end

  it "merge!; can merge key/value pairs from another structure, with a block to solve ties" do
    stm1 = SplayTreeMap.new({"a" => 100, "b" => 200})
    other1 = SplayTreeMap.new({"b" => 254, "c" => 300})
    stm2 = SplayTreeMap.new({1 => 1, 2 => 2})
    other2 = SplayTreeMap.new({2 => 4, 3 => 9})
    stm2.merge!(other2) { |_k, v1, v2| v1 + v2 }
    stm1.merge!(other1) { |_k, v1, v2| v1 + v2 }
    stm1["a"].should eq 100
    stm1["b"].should eq 454
    stm1["c"].should eq 300
  end

  it "merge; can merge a SplayTreeMap with another structure, expanding type signatures as necessary" do
    stm = SplayTreeMap.new({"foo" => "bar"})
    new_stm = stm.merge({"baz" => "qux"})
    new_stm["foo"].should eq "bar"
    new_stm["baz"].should eq "qux"
    stm["foo"].should eq "bar"
    stm["baz"]?.should be_nil

    new_stm = stm.merge({"1" => 1, "2" => 4, "3" => 9})
    new_stm["foo"].should eq "bar"
    new_stm["3"].should eq 9

    new_stm = stm.merge(["1", "2", "3"])
    new_stm["foo"].should eq "bar"
    new_stm["3"].should eq "3"

    new_stm = stm.merge([{"baz", "qux"}])
    new_stm["foo"].should eq "bar"
    new_stm["baz"].should eq "qux"
  end

  it "has_key?; can check a tree for a key, returning true or false" do
    stm = SplayTreeMap.new({"a" => 1, "b" => 2})
    stm.has_key?("a").should be_true
    stm.has_key?("c").should be_false
  end

  it "has_value?; can check a tree for a value, returning true or false" do
    stm = SplayTreeMap.new({"a" => 1, "b" => 2})
    stm.has_value?(2).should be_true
    stm.has_value?(4).should be_false
  end

  it "height; can return the max height of the current tree" do
    st = SplayTreeMap(Int32, Int32).new
    10.times { |x| st[x] = x }
    st.height.should eq 10
  end

  it "height(key); can return the height of a single element in the tree" do
    st = SplayTreeMap(Int32, Int32).new
    10.times { |x| st[x] = x }
    st.height(5).should eq 4
  end

  it "key_for; returns a key for a given value, and handles missing keys appropriately" do
    stm = SplayTreeMap.new({"foo" => "bar", "baz" => "qux"})
    (stm.key_for("bar", &.upcase)).should eq "foo"
    (stm.key_for("qix", &.upcase)).should eq "QIX"
    stm.key_for("bar").should eq "foo"
    stm.key_for("qux").should eq "baz"
    expect_raises(KeyError) do
      stm.key_for("foobar") # raises KeyError
    end
    stm.key_for?("bar").should eq "foo"
    stm.key_for?("qux").should eq "baz"
    stm.key_for?("foobar").should be_nil
  end

  it "keys; returns all of the keys in the tree" do
    st = SplayTreeMap(Int32, Int32).new
    log = [] of Int32
    10.times { |x| st[x] = x; log << x }

    st.keys.size.should eq 10
    st.keys.sort!.should eq log.sort

    stm = SplayTreeMap.new({"foo" => "bar", "baz" => "qux"})
    stm.keys.should eq ["baz", "foo"]
  end

  it "last; can find the last (largest) key" do
    st = SplayTreeMap(Int32, Int32).new
    10.times { |x| st[x] = x }

    st.last.should eq ({9, 9})
  end

  it "min; can find the min key" do
    st = SplayTreeMap(Int32, Int32).new
    10.times { |x| st[x] = x }

    st.min.should eq 0
  end

  it "reject; can create a new tree with select keys removed" do
    stm = SplayTreeMap.new({"a" => 100, "b" => 200, "c" => 300})
    res = stm.reject { |k, _v| k > "a" }
    res.size.should eq 1
    res["a"].should eq 100
    res.has_key?("b").should be_false
    res = stm.reject { |_k, v| v < 200 }
    res.size.should eq 2
    res.has_key?("a").should be_false
    res["c"].should eq 300
    res = SplayTreeMap.new({"a" => 1, "b" => 2, "c" => 3, "d" => 4}).reject("a", "c")
    res.size.should eq 2
    res["a"]?.should be_nil
    res["d"].should eq 4
    res = SplayTreeMap.new({"a" => 1, "b" => 2, "c" => 3, "d" => 4}).reject(["a", "c"])
    res.size.should eq 2
    res["a"]?.should be_nil
    res["d"].should eq 4
    res = SplayTreeMap.new({"a" => 1, "b" => 2, "c" => 3, "d" => 4}).reject({"a", "c"})
    res.size.should eq 2
    res["a"]?.should be_nil
    res["d"].should eq 4
  end

  it "reject!; can remove a set of keys from the current tree" do
    stm = SplayTreeMap.new({"a" => 100, "b" => 200, "c" => 300})
    stm.reject! { |k, _v| k > "a" }
    stm.size.should eq 1
    stm["a"].should eq 100
    stm.has_key?("b").should be_false
    stm = SplayTreeMap.new({"a" => 100, "b" => 200, "c" => 300})
    stm.reject! { |_k, v| v < 200 }
    stm.size.should eq 2
    stm.has_key?("a").should be_false
    stm["c"].should eq 300
    stm = SplayTreeMap.new({"a" => 1, "b" => 2, "c" => 3, "d" => 4})
    stm.reject!("a", "c")
    stm.size.should eq 2
    stm["a"]?.should be_nil
    stm["d"].should eq 4
    stm = SplayTreeMap.new({"a" => 1, "b" => 2, "c" => 3, "d" => 4})
    stm.reject!(["a", "c"])
    stm.size.should eq 2
    stm["a"]?.should be_nil
    stm["d"].should eq 4
    stm = SplayTreeMap.new({"a" => 1, "b" => 2, "c" => 3, "d" => 4})
    stm.reject!({"a", "c"})
    stm.size.should eq 2
    stm["a"]?.should be_nil
    stm["d"].should eq 4
  end

  it "select; can create a new tree that includes only specific keys" do
    stm = SplayTreeMap.new({"a" => 100, "b" => 200, "c" => 300}).select { |k, _v| k > "a" }
    stm.size.should eq 2
    stm["b"].should eq 200
    stm["c"].should eq 300
    stm = SplayTreeMap.new({"a" => 100, "b" => 200, "c" => 300}).select { |_k, v| v < 200 }
    stm.size.should eq 1
    stm["a"].should eq 100
    stm = SplayTreeMap.new({"a" => 1, "b" => 2, "c" => 3, "d" => 4}).select({"a", "c"})
    stm.size.should eq 2
    stm["a"].should eq 1
    stm["c"].should eq 3
    stm = SplayTreeMap.new({"a" => 1, "b" => 2, "c" => 3, "d" => 4}).select("a", "c")
    stm.size.should eq 2
    stm["a"].should eq 1
    stm["c"].should eq 3
    SplayTreeMap.new({"a" => 1, "b" => 2, "c" => 3, "d" => 4}).select(["a", "c"])
    stm.size.should eq 2
    stm["a"].should eq 1
    stm["c"].should eq 3
  end

  it "select!; can remove all keys from the current tree except for a small set" do
    stm = SplayTreeMap.new({"a" => 100, "b" => 200, "c" => 300})
    stm.select! { |k, _v| k > "a" }
    stm.size.should eq 2
    stm["b"].should eq 200
    stm["c"].should eq 300
    stm = SplayTreeMap.new({"a" => 100, "b" => 200, "c" => 300})
    stm.select! { |_k, v| v < 200 }
    stm.size.should eq 1
    stm["a"].should eq 100
    stm = SplayTreeMap.new({"a" => 1, "b" => 2, "c" => 3, "d" => 4})
    stm.select!({"a", "c"})
    stm.size.should eq 2
    stm["a"].should eq 1
    stm["c"].should eq 3
    stm = SplayTreeMap.new({"a" => 1, "b" => 2, "c" => 3, "d" => 4})
    stm.select!("a", "c")
    stm.size.should eq 2
    stm["a"].should eq 1
    stm["c"].should eq 3
    SplayTreeMap.new({"a" => 1, "b" => 2, "c" => 3, "d" => 4})
    stm.select!(["a", "c"])
    stm.size.should eq 2
    stm["a"].should eq 1
    stm["c"].should eq 3
  end

  it "to_a; can transform a SplayTreeMap into an array representation" do
    stm = SplayTreeMap.new({"foo" => "bar", "baz" => "qux"})
    ary = stm.to_a
    ary.should eq [{"baz", "qux"}, {"foo", "bar"}]
    stm2 = SplayTreeMap.new(ary)
    stm.should eq stm2
    (stm == stm2).should be_true
  end

  it "to_h; can transform a SplayTreeMap into a Hash representation" do
    stm = SplayTreeMap.new({"foo" => "bar", "baz" => "qux"})
    h = stm.to_h
    h["baz"].should eq "qux"
    h["foo"].should eq "bar"
  end

  it "to_s; can transform a SplayTreeMap into a String representation" do
    stm = SplayTreeMap.new({"foo" => "bar", "baz" => "qux"})
    stm.to_s.should eq %({ "baz" => "qux", "foo" => "bar" })
  end

  it "transform; can transform both the keys and the values of a tree to new types" do
    stm = SplayTreeMap.new({1 => 1, 2 => 4, 3 => 9, 4 => 16})
    stm = stm.transform { |k, v| {k.to_s, v.to_s} }
    stm["1"]?.should eq "1"
    stm["2"]?.should eq "4"
    stm["3"]?.should eq "9"
    stm["4"]?.should eq "16"
  end

  it "transform_keys; can transform the keys of a tree using a block" do
    stm = SplayTreeMap.new({:a => 1, :b => 2, :c => 3})
    stm = stm.transform_keys(&.to_s)
    stm["a"]?.should eq 1
    stm["b"]?.should eq 2
    stm["c"]?.should eq 3
  end

  it "transform_values; can transform the values of a tree using a block" do
    stm = SplayTreeMap.new({:a => 1, :b => 2, :c => 3})
    stm = stm.transform_values { |value| value + 1 }
    stm[:a].should eq 2
    stm[:b].should eq 3
    stm[:c].should eq 4
  end

  it "values; returns all of the values in the tree" do
    st = SplayTreeMap(Int32, Int32).new
    log = [] of Int32
    10.times { |x| st[x] = x; log << x }

    st.values.size.should eq 10
    st.values.sort!.should eq log.sort
  end

  it "values_at; returns a tuple with the associated values, and raises on invalid" do
    stm = SplayTreeMap.new({"a" => 1, "b" => 2, "c" => 3, "d" => 4})
    stm.values_at("a", "c").should eq ({1, 3})
    expect_raises(KeyError) do
      stm.values_at("a", "d", "e")
    end
  end

  it "values_at; returns a tuple with the associated values, and nil on invalid" do
    stm = SplayTreeMap.new({"a" => 1, "b" => 2, "c" => 3, "d" => 4})
    stm.values_at?("a", "c").should eq ({1, 3})
    stm.values_at?("a", "d", "e").should eq ({1, 4, nil})
  end

  it "zip; can combine two arrays into a single tree" do
    stm = SplayTreeMap.zip(["key1", "key2", "key3"], ["value1", "value2", "value3"])
    stm.size.should eq 3
    stm["key1"].should eq "value1"
    stm["key2"].should eq "value2"
    stm["key3"].should eq "value3"
  end

  it "can return an array of tuples of key and value" do
    st = SplayTreeMap(Int32, Int32).new
    log = [] of {Int32, Int32}
    10.times { |x| st[x] = x; log << {x, x} }

    a = st.to_a
    a.size.should eq 10

    a.sort.should eq log.sort
  end

  it "can prune the least used elements from a tree" do
    ins = {} of Int32 => Int32
    st = SplayTreeMap(Int32, Int32).new
    100000.times do
      loop do
        x = rand(10000000)
        if !ins.has_key?(x)
          ins[x] = x
          st[x] = x
          break
        end
      end
    end

    random_300 = ins.keys.shuffle![0..299]
    top_100 = random_300[0..99]
    intermediate_100 = random_300[100..199]
    _regular_100 = random_300[200..299]

    1000.times do
      100.times { st[intermediate_100.sample(1).first] }
      1000.times { st[top_100.sample(1).first] }
    end

    st.size.should eq 100000
    st.prune
    st.size.should be < 96000 # It should actually be around 90000, give or take, but because random numbers, may sometimes be higher.
  end

  it "can automatically enforce a maximum size" do
    ins = {} of Int32 => Int32
    st = SplayTreeMap(Int32, Int32).new
    100000.times do
      loop do
        x = Math.sqrt(rand(1000000000000)).to_i
        if !ins.has_key?(x)
          ins[x] = x
          st[x] = x
          break
        end
      end
    end
    st.size.should eq 100000

    st = SplayTreeMap(Int32, Int32).new
    st.maxsize = 10000
    100000.times do
      loop do
        x = Math.sqrt(rand(1000000000000)).to_i
        if !ins.has_key?(x)
          ins[x] = x
          st[x] = x
          break
        end
      end
    end
    st.size.should be <= 10000
  end

  it "should prune if a maxsize is set to a value less than the current size" do
    ins = {} of Int32 => Int32
    st = SplayTreeMap(Int32, Int32).new
    100000.times do
      loop do
        x = Math.sqrt(rand(1000000000000)).to_i
        if !ins.has_key?(x)
          ins[x] = x
          st[x] = x
          break
        end
      end
    end
    st.size.should eq 100000
    st.maxsize = 10000
    st.size.should be <= 10000
  end

  it "can report whether pruning occurred" do
    ins = {} of Int32 => Int32
    st = SplayTreeMap(Int32, Int32).new
    1000.times do
      loop do
        x = Math.sqrt(rand(100000000)).to_i
        if !ins.has_key?(x)
          ins[x] = x
          st[x] = x
          break
        end
      end
    end
    st.size.should eq 1000
    st.was_pruned?.should be_false

    st = SplayTreeMap(Int32, Int32).new
    st.maxsize = 10000
    10000.times do
      loop do
        x = Math.sqrt(rand(1000000000000)).to_i
        if !ins.has_key?(x)
          ins[x] = x
          st[x] = x
          break
        end
      end
    end
    st.size.should eq 10000
    full_set = st.values
    st.values.should eq full_set

    loop do
      x = Math.sqrt(rand(1000000000000)).to_i
      if !ins.has_key?(x)
        ins[x] = x
        st[x] = x
        break
      end
    end
    st.size.should be <= 10000
    st.was_pruned?.should be_true
  end

  it "can use a callback to collect pruned key/value pairs" do
    ins = {} of Int32 => Int32
    st = SplayTreeMap(Int32, Int32).new
    st.maxsize = 1000
    pruned_pairs = [] of {Int32, Int32}
    st.on_prune do |key, value| # collect the key/value pairs that were pruned
      pruned_pairs << {key, value}
    end
    1000.times do
      loop do
        x = Math.sqrt(rand(100000000)).to_i
        if !ins.has_key?(x)
          ins[x] = x
          st[x] = x
          break
        end
      end
    end
    st.size.should eq 1000
    st.was_pruned?.should be_false
    full_values = st.values

    loop do
      x = Math.sqrt(rand(1000000000000)).to_i
      if !ins.has_key?(x)
        ins[x] = x
        st[x] = x
        full_values << x
        break
      end
    end
    st.size.should be <= 1000
    st.was_pruned?.should be_true
    st.size.should eq (1001 - pruned_pairs.size)
    st.values.should eq (full_values - pruned_pairs.map { |x| x[1] })
  end
end
