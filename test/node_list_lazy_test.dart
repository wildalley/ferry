/// The node list builds only the rows on screen.
///
/// Subscriptions routinely carry two or three hundred nodes. Built all at
/// once, opening the nodes page — and every latency sort, which rebuilds it —
/// paid for every one of them; this holds the list to the rows in view.
library;

import 'package:ferry/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widget_test.dart' show buildState, node;

void main() {
  testWidgets('three hundred nodes build only the visible rows',
      (tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final harness = await buildState(
      nodes: [
        for (var i = 0; i < 300; i++)
          node('n$i', 'Node ${i.toString().padLeft(3, '0')}'),
      ],
    );
    addTearDown(harness.state.dispose);
    await tester.pumpWidget(SingBoxApp(state: harness.state));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.hub_outlined));
    await tester.pumpAndSettle();

    final built =
        find.textContaining(RegExp(r'^Node \d{3}$')).evaluate().length;
    expect(built, greaterThan(0));
    expect(built, lessThan(40),
        reason: 'a 900px window shows about a dozen rows; $built were built');

    // Scrolling reaches the end, so laziness has not cut the list short.
    await tester.scrollUntilVisible(
      find.text('Node 299'),
      600,
      // The page, not the horizontal filter-chip row inside it.
      scrollable: find
          .byWidgetPredicate(
              (w) => w is Scrollable && w.axisDirection == AxisDirection.down)
          .first,
    );
    expect(find.text('Node 299'), findsOneWidget);
  });
}
