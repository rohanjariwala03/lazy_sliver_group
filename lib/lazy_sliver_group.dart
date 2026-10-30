/// A [SliverMainAxisGroup] that builds its groups lazily.
library;

import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// A sliver that places [groupCount] slivers one after another along the main
/// axis, like [SliverMainAxisGroup], but only builds the groups that are
/// visible or in the cache area.
///
/// Each group is a sliver returned by [groupBuilder], typically a
/// [SliverMainAxisGroup] with a [PinnedHeaderSliver] and a [SliverList]. Pinned
/// headers behave as they do in [SliverMainAxisGroup]: they stay at the top
/// while their group is visible and are pushed away at the end of the group.
///
/// ```dart
/// CustomScrollView(
///   slivers: [
///     LazySliverMainAxisGroup(
///       groupCount: days.length,
///       groupBuilder: (context, index) => SliverMainAxisGroup(
///         slivers: [
///           PinnedHeaderSliver(child: DayHeader(days[index])),
///           SliverList.builder(
///             itemCount: days[index].messages.length,
///             itemBuilder: (context, i) => MessageTile(days[index].messages[i]),
///           ),
///         ],
///       ),
///     ),
///   ],
/// )
/// ```
///
/// The extent of a group that has not been built yet is estimated from the
/// groups that have. When a group above the viewport turns out to have a
/// different extent, the scroll offset is corrected so that the visible
/// content does not move.
///
/// The state of a group is lost when it scrolls out of the cache area.
///
/// This sliver cannot be placed before the center sliver of a scroll view.
class LazySliverMainAxisGroup extends RenderObjectWidget {
  /// Creates a sliver that builds [groupCount] groups on demand.
  const LazySliverMainAxisGroup({
    super.key,
    required this.groupCount,
    required this.groupBuilder,
  }) : assert(groupCount >= 0);

  /// The number of groups.
  final int groupCount;

  /// Builds the group at the given index. Must return a sliver.
  final IndexedWidgetBuilder groupBuilder;

  @override
  RenderObjectElement createElement() => _LazyGroupElement(this);

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderLazyGroup(context as _LazyGroupElement);
}

class _LazyGroupElement extends RenderObjectElement {
  _LazyGroupElement(LazySliverMainAxisGroup super.widget);

  final SplayTreeMap<int, Element> _children = SplayTreeMap<int, Element>();
  RenderSliver? _currentBeforeChild;

  @override
  LazySliverMainAxisGroup get widget => super.widget as LazySliverMainAxisGroup;

  @override
  _RenderLazyGroup get renderObject => super.renderObject as _RenderLazyGroup;

  int get groupCount => widget.groupCount;

  @override
  void update(LazySliverMainAxisGroup newWidget) {
    super.update(newWidget);
    // The builder is usually a new closure, so rebuild the groups that exist.
    performRebuild();
    renderObject.markNeedsLayout();
  }

  @override
  void performRebuild() {
    super.performRebuild();
    _currentBeforeChild = null;
    for (final int index in _children.keys.toList()) {
      _updateGroup(index);
    }
  }

  void _updateGroup(int index) {
    final Element? child = updateChild(
      _children[index],
      index < groupCount ? widget.groupBuilder(this, index) : null,
      index,
    );
    if (child == null) {
      _children.remove(index);
    } else {
      _children[index] = child;
      _currentBeforeChild = child.renderObject! as RenderSliver;
    }
  }

  /// Builds the group at [index] and inserts it after [after].
  void createGroup(int index, {required RenderSliver? after}) {
    owner!.buildScope(this, () {
      _currentBeforeChild = after;
      _updateGroup(index);
    });
  }

  void removeGroup(RenderSliver child) {
    final int index = (child.parentData! as _GroupParentData).index;
    owner!.buildScope(this, () {
      updateChild(_children[index], null, index);
      _children.remove(index);
    });
  }

  @override
  void forgetChild(Element child) {
    _children.remove(child.slot);
    super.forgetChild(child);
  }

  @override
  void visitChildren(ElementVisitor visitor) {
    _children.values.forEach(visitor);
  }

  @override
  void insertRenderObjectChild(RenderObject child, int slot) {
    renderObject.insert(child as RenderSliver, after: _currentBeforeChild);
    (child.parentData! as _GroupParentData).index = slot;
  }

  @override
  void moveRenderObjectChild(RenderObject child, int oldSlot, int newSlot) {
    // Groups never change index: each index always has its own slot.
    assert(false);
  }

  @override
  void removeRenderObjectChild(RenderObject child, int slot) {
    renderObject.remove(child as RenderSliver);
  }
}

class _GroupParentData extends SliverPhysicalContainerParentData {
  int index = 0;

  /// The scroll offset of the start of this group within the parent sliver.
  double layoutOffset = 0;
}

class _RenderLazyGroup extends RenderSliver
    with ContainerRenderObjectMixin<RenderSliver, _GroupParentData> {
  _RenderLazyGroup(this._element);

  final _LazyGroupElement _element;

  /// The last measured scroll extent of each group, or null if never built.
  // ponytail: offsets are recomputed by summing this list on every layout,
  // O(groupCount). Use a Fenwick tree if lists reach hundreds of thousands.
  final List<double?> _extents = <double?>[];

  /// Whether the extent in [_extents] was measured with the whole group built,
  /// so it is not itself an estimate of a partly built list.
  final List<bool> _exact = <bool>[];

  /// The group at the top of the viewport after the last layout, and its
  /// offset. Its position must not change, so that the content on screen does
  /// not move when the extents of groups above it are corrected.
  int? _anchorIndex;
  double _anchorOffset = 0;

  @override
  void setupParentData(RenderObject child) {
    if (child.parentData is! _GroupParentData) {
      child.parentData = _GroupParentData();
    }
  }

  int _indexOf(RenderSliver child) => (child.parentData! as _GroupParentData).index;

  /// The average extent of the measured groups, preferring exact ones.
  double? _averageExtent() {
    var sum = 0.0;
    var count = 0;
    var exactSum = 0.0;
    var exactCount = 0;
    for (var i = 0; i < _extents.length; i++) {
      final double? extent = _extents[i];
      if (extent != null) {
        sum += extent;
        count++;
        if (_exact[i]) {
          exactSum += extent;
          exactCount++;
        }
      }
    }
    if (exactCount > 0) {
      return exactSum / exactCount;
    }
    return count == 0 ? null : sum / count;
  }

  /// Returns the group at [index] after [after], and whether it was created.
  (RenderSliver, bool) _obtainGroup(int index, {required RenderSliver? after}) {
    final RenderSliver? existing = after == null ? firstChild : childAfter(after);
    if (existing != null && _indexOf(existing) == index) {
      return (existing, false);
    }
    invokeLayoutCallback<SliverConstraints>((_) {
      _element.createGroup(index, after: after);
    });
    return (after == null ? firstChild! : childAfter(after)!, true);
  }

  void _removeGroup(RenderSliver child) {
    invokeLayoutCallback<SliverConstraints>((_) => _element.removeGroup(child));
  }

  @override
  void performLayout() {
    assert(
      constraints.growthDirection == GrowthDirection.forward,
      'LazySliverMainAxisGroup cannot be placed before the center sliver.',
    );
    final int groupCount = _element.groupCount;
    if (_extents.length > groupCount) {
      _extents.length = groupCount;
      _exact.length = groupCount;
    } else {
      _extents.addAll(List<double?>.filled(groupCount - _extents.length, null));
      _exact.addAll(List<bool>.filled(groupCount - _exact.length, false));
    }
    if (_anchorIndex != null && _anchorIndex! >= groupCount) {
      _anchorIndex = null;
    }

    final double scrollOffset = constraints.scrollOffset;
    final double cacheStart = scrollOffset + constraints.cacheOrigin;
    final double cacheEnd = cacheStart + constraints.remainingCacheExtent;
    final double? averageExtent = _averageExtent();
    double extentOf(int index) => _extents[index] ?? averageExtent ?? 0;

    // Find the first group that reaches into the cache area. Positions are
    // taken relative to the built groups, so a changing estimate for unbuilt
    // groups never moves a built one.
    var firstIndex = 0;
    var firstOffset = 0.0;
    if (firstChild != null) {
      firstIndex = _indexOf(firstChild!);
      firstOffset = (firstChild!.parentData! as _GroupParentData).layoutOffset;
      while (firstIndex > 0 && firstOffset > cacheStart) {
        firstIndex--;
        firstOffset -= extentOf(firstIndex);
      }
    }
    while (averageExtent != null &&
        firstIndex < groupCount - 1 &&
        firstOffset + extentOf(firstIndex) <= cacheStart) {
      firstOffset += extentOf(firstIndex);
      firstIndex++;
    }

    // Estimates for the groups before the built ones were off, so the first
    // group would not be at 0. Move everything, and the scroll offset, so that
    // it is.
    if (firstOffset < 0 || firstIndex == 0) {
      var firstGroupOffset = firstOffset;
      for (var i = 0; i < firstIndex; i++) {
        firstGroupOffset -= extentOf(i);
      }
      final double shift = _fixPrecisionError(-firstGroupOffset);
      if (shift != 0) {
        for (RenderSliver? child = firstChild; child != null; child = childAfter(child)) {
          (child.parentData! as _GroupParentData).layoutOffset += shift;
        }
        _anchorOffset += shift;
        geometry = SliverGeometry(scrollOffsetCorrection: shift);
        return;
      }
    }

    while (firstChild != null && _indexOf(firstChild!) < firstIndex) {
      _removeGroup(firstChild!);
    }

    // From here on, this follows RenderSliverMainAxisGroup.performLayout,
    // starting at the first built group instead of the first group.
    double groupOffset = firstOffset;
    double layoutOffset = 0;
    double maxPaintExtent = 0;
    double paintOffset = constraints.overlap;
    double cacheOrigin = constraints.cacheOrigin;
    double remainingCacheExtent = constraints.remainingCacheExtent;

    double maxScrollObstructionExtent = 0;
    double scrollOffsetCorrection = 0;
    RenderSliver? previous;
    var index = firstIndex;
    // Lay out at least one group, so that there is an estimate for the others
    // even when this sliver starts below the cache area.
    while (index < groupCount &&
        (groupOffset < cacheEnd || (previous == null && averageExtent == null))) {
      final (RenderSliver child, bool created) = _obtainGroup(index, after: previous);
      final childParentData = child.parentData! as _GroupParentData;
      if (index == _anchorIndex && !created) {
        scrollOffsetCorrection = _fixPrecisionError(groupOffset - _anchorOffset);
        _anchorOffset = groupOffset;
      }
      final double beforeOffsetPaintExtent = calculatePaintOffset(
        constraints,
        from: 0.0,
        to: groupOffset,
      );
      final double childScrollOffset = math.max(0.0, scrollOffset - groupOffset);
      final double correctedCacheOrigin = math.max(cacheOrigin, -childScrollOffset);
      final double cacheExtentCorrection = cacheOrigin - correctedCacheOrigin;

      child.layout(
        constraints.copyWith(
          scrollOffset: childScrollOffset,
          cacheOrigin: correctedCacheOrigin,
          overlap: math.max(0.0, _fixPrecisionError(paintOffset - beforeOffsetPaintExtent)),
          remainingPaintExtent: _fixPrecisionError(
            constraints.remainingPaintExtent - beforeOffsetPaintExtent,
          ),
          remainingCacheExtent: math.max(
            0.0,
            _fixPrecisionError(remainingCacheExtent + cacheExtentCorrection),
          ),
          precedingScrollExtent: groupOffset + constraints.precedingScrollExtent,
        ),
        parentUsesSize: true,
      );
      final SliverGeometry childGeometry = child.geometry!;
      if (childGeometry.scrollOffsetCorrection != null) {
        geometry = SliverGeometry(scrollOffsetCorrection: childGeometry.scrollOffsetCorrection);
        return;
      }

      _extents[index] = childGeometry.scrollExtent;
      _exact[index] =
          groupOffset >= cacheStart && groupOffset + childGeometry.scrollExtent <= cacheEnd;
      childParentData.layoutOffset = groupOffset;
      final double childPaintOffset = layoutOffset + childGeometry.paintOrigin;
      childParentData.paintOffset = switch (constraints.axis) {
        Axis.vertical => Offset(0.0, childPaintOffset),
        Axis.horizontal => Offset(childPaintOffset, 0.0),
      };
      groupOffset += childGeometry.scrollExtent;
      layoutOffset += childGeometry.layoutExtent;
      maxPaintExtent += childGeometry.maxPaintExtent;
      maxScrollObstructionExtent += childGeometry.maxScrollObstructionExtent;
      paintOffset = math.max(childPaintOffset + childGeometry.paintExtent, paintOffset);
      if (childGeometry.cacheExtent != 0.0) {
        remainingCacheExtent = _fixPrecisionError(
          remainingCacheExtent - childGeometry.cacheExtent - cacheExtentCorrection,
        );
        cacheOrigin = math.min(correctedCacheOrigin + childGeometry.cacheExtent, 0.0);
      }
      previous = child;
      index++;
    }

    if (scrollOffsetCorrection != 0) {
      geometry = SliverGeometry(scrollOffsetCorrection: scrollOffsetCorrection);
      return;
    }

    RenderSliver? trailing = previous == null ? firstChild : childAfter(previous);
    while (trailing != null) {
      final RenderSliver? next = childAfter(trailing);
      _removeGroup(trailing);
      trailing = next;
    }

    _anchorIndex = null;
    for (RenderSliver? child = firstChild; child != null; child = childAfter(child)) {
      final childParentData = child.parentData! as _GroupParentData;
      if (childParentData.layoutOffset + child.geometry!.scrollExtent > scrollOffset) {
        _anchorIndex = childParentData.index;
        _anchorOffset = childParentData.layoutOffset;
        break;
      }
    }

    // Groups after the last built one are estimated.
    final double? updatedAverage = _averageExtent();
    var scrollExtent = groupOffset;
    for (var i = index; i < groupCount; i++) {
      scrollExtent += _extents[i] ?? updatedAverage ?? 0;
    }
    maxPaintExtent += firstOffset + (scrollExtent - groupOffset);

    // Keep pinned children within the end of this sliver.
    final double remainingExtent = math.max(0, scrollExtent - scrollOffset);
    if (paintOffset > remainingExtent) {
      final bool pinnedChildrenOverflow =
          maxScrollObstructionExtent > remainingExtent - constraints.overlap;
      final double paintCorrection = paintOffset - remainingExtent;
      paintOffset = remainingExtent;
      for (RenderSliver? child = firstChild; child != null; child = childAfter(child)) {
        final childParentData = child.parentData! as _GroupParentData;
        final double childMainAxisPaintOffset = switch (constraints.axis) {
          Axis.vertical => childParentData.paintOffset.dy,
          Axis.horizontal => childParentData.paintOffset.dx,
        };
        final bool childIsPinned = child.geometry!.maxScrollObstructionExtent > 0;
        if (childMainAxisPaintOffset + child.geometry!.paintExtent > remainingExtent ||
            (pinnedChildrenOverflow && childIsPinned)) {
          childParentData.paintOffset = switch (constraints.axis) {
            Axis.vertical => Offset(0.0, childParentData.paintOffset.dy - paintCorrection),
            Axis.horizontal => Offset(childParentData.paintOffset.dx - paintCorrection, 0.0),
          };
        }
      }
    }

    final double paintExtent = clampDouble(paintOffset, 0, constraints.remainingPaintExtent);
    geometry = SliverGeometry(
      scrollExtent: scrollExtent,
      paintExtent: paintExtent,
      cacheExtent: calculateCacheOffset(
        constraints,
        from: math.min(scrollOffset, 0),
        to: scrollExtent,
      ),
      maxPaintExtent: maxPaintExtent,
      hasVisualOverflow: scrollExtent > constraints.remainingPaintExtent || scrollOffset > 0.0,
    );

    // Flip the paint offsets for reversed axes, now that paintExtent is known.
    for (RenderSliver? child = firstChild; child != null; child = childAfter(child)) {
      final childParentData = child.parentData! as _GroupParentData;
      childParentData.paintOffset = switch (constraints.axisDirection) {
        AxisDirection.up => Offset(
            0.0,
            paintExtent - childParentData.paintOffset.dy - child.geometry!.paintExtent,
          ),
        AxisDirection.left => Offset(
            paintExtent - childParentData.paintOffset.dx - child.geometry!.paintExtent,
            0.0,
          ),
        AxisDirection.right || AxisDirection.down => childParentData.paintOffset,
      };
    }
  }

  @override
  double? childScrollOffset(RenderObject child) =>
      (child.parentData! as _GroupParentData).layoutOffset;

  @override
  double childMainAxisPosition(RenderSliver child) {
    final childParentData = child.parentData! as _GroupParentData;
    return switch (constraints.axisDirection) {
      AxisDirection.down => childParentData.paintOffset.dy,
      AxisDirection.right => childParentData.paintOffset.dx,
      AxisDirection.up =>
        geometry!.paintExtent - child.geometry!.paintExtent - childParentData.paintOffset.dy,
      AxisDirection.left =>
        geometry!.paintExtent - child.geometry!.paintExtent - childParentData.paintOffset.dx,
    };
  }

  @override
  double childCrossAxisPosition(RenderSliver child) => 0.0;

  @override
  void applyPaintTransform(RenderSliver child, Matrix4 transform) {
    (child.parentData! as _GroupParentData).applyPaintTransform(transform);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    // Paint later groups first so that pinned headers of earlier groups stay
    // on top, as in RenderSliverMainAxisGroup.
    for (RenderSliver? child = lastChild; child != null; child = childBefore(child)) {
      if (child.geometry!.visible) {
        final childParentData = child.parentData! as _GroupParentData;
        context.paintChild(child, offset + childParentData.paintOffset);
      }
    }
  }

  @override
  bool hitTestChildren(
    SliverHitTestResult result, {
    required double mainAxisPosition,
    required double crossAxisPosition,
  }) {
    for (RenderSliver? child = firstChild; child != null; child = childAfter(child)) {
      if (!child.geometry!.visible) {
        continue;
      }
      final bool isHit = result.addWithAxisOffset(
        mainAxisPosition: mainAxisPosition,
        crossAxisPosition: crossAxisPosition,
        paintOffset: (child.parentData! as _GroupParentData).paintOffset,
        mainAxisOffset: childMainAxisPosition(child),
        crossAxisOffset: childCrossAxisPosition(child),
        hitTest: child.hitTest,
      );
      if (isHit) {
        return true;
      }
    }
    return false;
  }

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    for (RenderSliver? child = firstChild; child != null; child = childAfter(child)) {
      if (child.geometry!.visible || child.geometry!.cacheExtent > 0.0) {
        visitor(child);
      }
    }
  }

  static double _fixPrecisionError(double number) {
    return number.abs() < precisionErrorTolerance ? 0.0 : number;
  }
}
