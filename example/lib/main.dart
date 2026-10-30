import 'package:flutter/material.dart';
import 'package:lazy_sliver_group/lazy_sliver_group.dart';

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'lazy_sliver_group',
      theme: ThemeData(colorSchemeSeed: Colors.teal),
      home: const ChatHistory(),
    );
  }
}

/// About five years of chat history: one group per day, each with a pinned
/// date header. Only the days on screen are built.
class ChatHistory extends StatelessWidget {
  const ChatHistory({super.key});

  static const int dayCount = 2000;

  // Days have different numbers of messages, so their extents differ.
  static int messageCountOf(int day) => 1 + (day * 7) % 12;

  @override
  Widget build(BuildContext context) {
    final DateTime today = DateUtils.dateOnly(DateTime.now());
    return Scaffold(
      appBar: AppBar(title: const Text('$dayCount days of messages')),
      body: CustomScrollView(
        slivers: [
          LazySliverMainAxisGroup(
            groupCount: dayCount,
            groupBuilder: (BuildContext context, int day) =>
                SliverMainAxisGroup(
              slivers: [
                PinnedHeaderSliver(
                    child: _DayHeader(today.subtract(Duration(days: day)))),
                SliverList.builder(
                  itemCount: messageCountOf(day),
                  itemBuilder: (BuildContext context, int message) => _Message(
                      text: 'Day $day, message $message', mine: message.isEven),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader(this.date);

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return ColoredBox(
      color: colors.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Center(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.secondaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Text(
                  MaterialLocalizations.of(context).formatMediumDate(date)),
            ),
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text, required this.mine});

  final String text;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color:
              mine ? colors.primaryContainer : colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(text),
      ),
    );
  }
}
