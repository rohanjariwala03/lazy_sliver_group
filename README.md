# lazy_sliver_group

A `SliverMainAxisGroup` that builds its groups lazily.

Use it to show thousands of sliver groups in one scroll view, for example years of chat history with a pinned date header per day. Only the groups that are visible or in the cache area are built. See [flutter/flutter#160075](https://github.com/flutter/flutter/issues/160075).

```dart
CustomScrollView(
  slivers: [
    LazySliverMainAxisGroup(
      groupCount: days.length,
      groupBuilder: (context, index) => SliverMainAxisGroup(
        slivers: [
          PinnedHeaderSliver(child: DayHeader(days[index])),
          SliverList.builder(
            itemCount: days[index].messages.length,
            itemBuilder: (context, i) => MessageTile(days[index].messages[i]),
          ),
        ],
      ),
    ),
  ],
)
```

## Why

With a plain `CustomScrollView`, you can make each day a `SliverMainAxisGroup`, but every day is built and laid out on every rebuild. With 2000 days, that makes `setState` slow. Flattening everything into one `SliverList` keeps it lazy, but you lose sliver features such as pinned headers per group.

`LazySliverMainAxisGroup` keeps both:

- Groups are built on demand, like the items of a `SliverList`. A rebuild only rebuilds the built groups.
- Jumping far, for example with `jumpTo`, builds only the groups at the target, not the groups in between.
- Each group can be any sliver. Pinned headers behave as in `SliverMainAxisGroup`: they stay at the top while their group is visible and are pushed away at its end.
- It works in reversed scroll views.

## How positions are estimated

The extent of a group that has not been built yet is estimated from the average extent of the groups that have. When the estimate changes, or a group above the viewport turns out larger or smaller than estimated, the scroll offset is corrected so that the visible content does not move.

Because of this, the total scroll extent and the scroll offset are estimates until all groups have been built, as with `SliverList`. A scrollbar thumb can jump when groups of very different sizes are measured.

## Limitations

- The state of a group is lost when it scrolls out of the cache area. There is no keep-alive support yet.
- Groups are identified by index. If you insert a group at the start, the groups after it are rebuilt for their new index.
- It cannot be placed before the `center` sliver of a scroll view.
