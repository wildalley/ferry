/// On a phone the node and rule rows fold their side buttons into one menu,
/// so the name or the rule keeps the width. The actions must still be there.
library;

import 'package:ferry/main.dart';
import 'package:ferry/models/custom_rule.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widget_test.dart' show buildState, node;

Future<void> _size(WidgetTester tester, double width) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('a phone node row favourites through its menu', (tester) async {
    await _size(tester, 390);
    final harness = await buildState(nodes: [node('a', 'Tokyo')]);
    addTearDown(harness.state.dispose);
    await tester.pumpWidget(SingBoxApp(state: harness.state));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.hub_outlined));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.star_border_rounded), findsNothing,
        reason: 'the star button is folded away on a phone');
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add to favorites'));
    await tester.pumpAndSettle();

    expect(harness.state.nodes.single.favorite, isTrue);
    expect(find.byIcon(Icons.star_rounded), findsOneWidget,
        reason: 'a favourite is marked beside the name');
  });

  testWidgets('a desktop node row keeps its buttons', (tester) async {
    await _size(tester, 1280);
    final harness = await buildState(nodes: [node('a', 'Tokyo')]);
    addTearDown(harness.state.dispose);
    await tester.pumpWidget(SingBoxApp(state: harness.state));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.hub_outlined).first);
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.star_border_rounded), findsOneWidget);
    expect(find.byTooltip('More'), findsNothing);
  });

  testWidgets('a phone rule row removes through its menu', (tester) async {
    await _size(tester, 390);
    final harness = await buildState(nodes: [node('a', 'Tokyo')]);
    addTearDown(harness.state.dispose);
    await harness.state.addCustomRule(const CustomRule(
      id: 'r1',
      matcher: RuleMatcher.domainSuffix,
      value: 'work.example.cn',
      target: RuleTarget.direct,
    ));
    await tester.pumpWidget(SingBoxApp(state: harness.state));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.alt_route_outlined));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.keyboard_arrow_up), findsNothing);
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();

    expect(harness.state.customRules, isEmpty);
  });
}
