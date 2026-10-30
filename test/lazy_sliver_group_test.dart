import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lazy_sliver_group/lazy_sliver_group.dart';

const double headerExtent = 40;
const double itemExtent = 50;

// Uneven groups, so estimated extents are wrong and need corrections.
int itemCountOf(int group) => 3 + group % 5;
double extentOf(int group) => headerExtent + itemExtent * itemCountOf(group);

void main() {
  late Set<int> built;
  late ScrollController controller;
  var taps = <String>[];

  setUp(() {
    built = <int>{};
    taps = <String>[];
    controller = ScrollController();
  });
  tearDown(() => controller.dispose());

  Future<void> pumpGroups(WidgetTester tester, {int groupCount = 2000, bool reverse = false}) {
    return tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: CustomScrollView(
          controller: controller,
          reverse: reverse,
          slivers: <Widget>[
            LazySliverMainAxisGroup(
              groupCount: groupCount,
              groupBuilder: (BuildContext context, int group) {
                built.add(group);
                return SliverMainAxisGroup(
                  slivers: <Widget>[
                    PinnedHeaderSliver(
                      child: SizedBox(height: headerExtent, child: Text('header $group')),
                    ),
                    SliverFixedExtentList.builder(
                      itemExtent: itemExtent,
                      itemCount: itemCountOf(group),
                      itemBuilder: (BuildContext context, int item) => GestureDetector(
                        onTap: () => taps.add('g$group i$item'),
                        child: Text('g$group i$item'),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  double topOf(WidgetTester tester, String text) => tester.getTopLeft(find.text(text)).dy;

  testWidgets('builds only the groups near the viewport', (WidgetTester tester) async {
    await pumpGroups(tester);

    expect(built.length, lessThan(10));
    expect(find.text('header 0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a rebuild only rebuilds the built groups', (WidgetTester tester) async {
    await pumpGroups(tester);
    built.clear();

    await pumpGroups(tester);

    expect(built, isNotEmpty);
    expect(built.length, lessThan(10));
  });

  testWidgets('jumping far builds only the groups at the target', (WidgetTester tester) async {
    await pumpGroups(tester);
    built.clear();

    controller.jumpTo(100000);
    await tester.pump();

    expect(built, isNotEmpty);
    expect(built.length, lessThan(10));
    expect(built.reduce((int a, int b) => a < b ? a : b), greaterThan(100));
    expect(tester.takeException(), isNull);
  });

  testWidgets('pins the header of the current group', (WidgetTester tester) async {
    await pumpGroups(tester);

    controller.jumpTo(100);
    await tester.pump();
    expect(topOf(tester, 'header 0'), 0);

    // Group 0 ends at 190, so at 170 its header is pushed 20 px out.
    controller.jumpTo(170);
    await tester.pump();
    expect(topOf(tester, 'header 0'), -20);

    controller.jumpTo(extentOf(0) + 60);
    await tester.pump();
    expect(topOf(tester, 'header 1'), 0);
  });

  testWidgets('content stays in place while scrolling up after a jump', (
    WidgetTester tester,
  ) async {
    await pumpGroups(tester);
    controller.jumpTo(50000);
    await tester.pump();

    while (controller.offset > 0) {
      final Finder anchor = find.textContaining(RegExp(r'^g\d+ i\d+$')).first;
      final String text = (tester.widget<Text>(anchor)).data!;
      final double before = topOf(tester, text);

      controller.jumpTo((controller.offset - 120).clamp(0, double.infinity));
      await tester.pump();

      final double moved = topOf(tester, text) - before;
      // The move can be less than 120 only when the top was reached exactly.
      if (controller.offset > 0) {
        expect(moved, moreOrLessEquals(120), reason: '$text at ${controller.offset}');
      }
    }

    expect(controller.offset, 0);
    expect(topOf(tester, 'header 0'), 0);
    expect(topOf(tester, 'g0 i0'), headerExtent);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pinned headers never cover the next header after a jump', (
    WidgetTester tester,
  ) async {
    await pumpGroups(tester);
    controller.jumpTo(50000);
    await tester.pump();

    for (var step = 0; step < 100; step++) {
      controller.jumpTo(controller.offset + 7);
      await tester.pump();
      final List<(int, double)> headers = find
          .textContaining(RegExp(r'^header \d+$'))
          .evaluate()
          .map(
            (Element e) => (
              int.parse((e.widget as Text).data!.split(' ').last),
              tester.getTopLeft(find.byWidget(e.widget)).dy,
            ),
          )
          .toList()
        ..sort((a, b) => a.$1.compareTo(b.$1));
      for (var i = 0; i + 1 < headers.length; i++) {
        final (int group, double top) = headers[i];
        final (int nextGroup, double nextTop) = headers[i + 1];
        expect(nextGroup, group + 1);
        expect(top + headerExtent, lessThanOrEqualTo(nextTop + precisionErrorTolerance));
      }
      expect(headers.first.$2, lessThanOrEqualTo(0));
    }
    expect(tester.takeException(), isNull);
  });

  // Groups whose SliverList estimates its own extent, as real content does.
  Widget variableGroup(BuildContext context, int group) => SliverMainAxisGroup(
        slivers: <Widget>[
          PinnedHeaderSliver(child: SizedBox(height: headerExtent, child: Text('header $group'))),
          SliverList.builder(
            itemCount: 5 + group % 30,
            itemBuilder: (BuildContext context, int item) => SizedBox(
                height: 20.0 + (group * 37 + item * 13) % 200, child: Text('g$group i$item')),
          ),
        ],
      );

  testWidgets('the scroll offset follows scrolling up after a jump', (WidgetTester tester) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: CustomScrollView(
          controller: controller,
          slivers: <Widget>[
            LazySliverMainAxisGroup(groupCount: 2000, groupBuilder: variableGroup),
          ],
        ),
      ),
    );
    controller.jumpTo(80000);
    await tester.pump();

    for (var step = 0; step < 12; step++) {
      final double before = controller.offset;
      controller.jumpTo(before - 500);
      await tester.pump();
      // Corrections are limited to the error of the groups that were just
      // measured, not the estimate for every unbuilt group above.
      expect((controller.offset - before).abs(), lessThan(2000));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('estimates its extent when it starts below the cache area', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: CustomScrollView(
          controller: controller,
          slivers: <Widget>[
            const SliverToBoxAdapter(child: SizedBox(height: 2000)),
            LazySliverMainAxisGroup(groupCount: 100, groupBuilder: variableGroup),
          ],
        ),
      ),
    );

    expect(controller.position.maxScrollExtent, greaterThan(2000 + 100 * headerExtent - 600));
  });

  testWidgets('works in a reversed scroll view', (WidgetTester tester) async {
    await pumpGroups(tester, reverse: true);

    expect(tester.getBottomLeft(find.text('header 0')).dy, 600);
    expect(tester.getBottomLeft(find.text('g0 i0')).dy, 600 - headerExtent);
  });

  testWidgets('taps reach items in groups', (WidgetTester tester) async {
    await pumpGroups(tester);

    await tester.tap(find.text('g1 i2'));

    expect(taps, <String>['g1 i2']);
  });

  testWidgets('removes groups when the count shrinks', (WidgetTester tester) async {
    await pumpGroups(tester);
    await pumpGroups(tester, groupCount: 1);

    expect(find.text('header 0'), findsOneWidget);
    expect(find.text('header 1', skipOffstage: false), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
