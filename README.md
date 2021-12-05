![SplayTreeMap CI](https://img.shields.io/github/workflow/status/wyhaines/splay_tree_map.cr/SplayTreeMap%20CI?style=for-the-badge&logo=GitHub)
[![GitHub release](https://img.shields.io/github/release/wyhaines/splay_tree_map.cr.svg?style=for-the-badge)](https://github.com/wyhaines/splay_tree_map.cr/releases)
![GitHub commits since latest release (by SemVer)](https://img.shields.io/github/commits-since/wyhaines/splay_tree_map.cr/latest?style=for-the-badge)

# [Splay Tree Map](https://wyhaines.github.io/splay_tree_map.cr/)

A splay tree is a type of [binary search](https://en.wikipedia.org/wiki/Binary_search_tree) tree that self organizes so that the most frequently accessed items tend to be towards theroot of the tree, where they can be accessed more quickly.

This implementation provides a [hash-like](https://crystal-lang.org/api/latest/Hash.html) interface, and it provides a couple
features not typically found in Splay Trees -- efficient removal of the items
that are generally least frequently accessed, and an extra fast search option.

### Leaf Pruning

Because splay trees tend to organize themselves with the most frequently
accessed elements towards the root of the tree, the least frequently accessed
items tend to migrate towards the leaves of the tree. This implementation
offers a method that can be used to prune its leaves, which generally has the
effect of removing the least frequently accessed items from the tree.

This is useful if the data structure is being used to implement a cache, as
it can be used to control the size of the cache while generaly keeping the
most useful items in the cache without any other extensive bookkeeping.

### Search without Splaying

A splay operation is generally performed on any access to a splay tree. This is
the operation that moves the most important items towards the root. This operation
has a cost to it, however, and there are times when it is desireable to search the
hash without a splay operation occuring for the key that is searched. This results
in a faster search operation, at the cost of not performing any efficiency improving
structural changes to the tree. This should not be the primary search method that
is used, but it can be useful at the right time.

### Maximum Size

If `#maxsize` is set to an integer alue, then the splay tree will perform a prune
operation when the maximum size of the tree is reached. This is useful for implementing
a cache.

## Installation

1. Add the dependency to your `shard.yml`:

   ```yaml
   dependencies:
     splay_tree_map:
       github: wyhaines/splay_tree_map.cr
   ```

2. Run `shards install`

## Usage

Full documentation can be found at: [https://wyhaines.github.io/splay_tree_map.cr/index.html](https://wyhaines.github.io/splay_tree_map.cr/index.html)

```crystal
require "splay_tree_map"
```

Generally, the data structure is used like a hash.

```crystal
stm = SplayTreeMap(String, String).new
stm.maxsize = 10

stm["this"] = "that"
stm["something"] = "else"
stm["junk"] = "pile"

if stm.has_key?("this")
  puts stm["this"]
end

stm.delete("junk")

puts stm.obtain("something") # This finds, but doesn't splay.

stm.prune # remove all leaves
```

## Testing

To run the specs run `crystal spec`.  To run specs with more debugging output use `LOG_LEVEL=DEBUG crystal spec`.

## TODO

Experiment with other variations of splay operations, such as lazy semi-splay
to see if performance can be improved. Right now this isn't any better than
just using a Hash and arbitrarily deleting half of the hash if it grows too big.

## Credits

This implementation is derived from the incomplete and broken implementation
in the Crystalline shard found at https://github.com/jtomschroeder/crystalline

## Contributing

1. Fork it (<https://github.com/wyhaines/splay_tree_map/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [Kirk Haines](https://github.com/wyhaines) - creator and maintainer

![GitHub code size in bytes](https://img.shields.io/github/languages/code-size/wyhaines/splay_tree_map.cr?style=for-the-badge)
![GitHub issues](https://img.shields.io/github/issues/wyhaines/splay_tree_map.cr?style=for-the-badge)
