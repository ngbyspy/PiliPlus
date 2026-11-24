import 'package:PiliPlus/utils/route_scroll_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets(
    'restores both video page scroll areas and clamps shortened content',
    (tester) async {
      final outer = ScrollController();
      final intro = ScrollController();
      final detached = ScrollController();
      Widget page(int count) => MaterialApp(
        home: Column(
          children: [
            for (final controller in [outer, intro])
              Expanded(
                child: ListView.builder(
                  controller: controller,
                  itemExtent: 60,
                  itemCount: count,
                  itemBuilder: (_, i) => Text('条目 $i'),
                ),
              ),
          ],
        ),
      );
      await tester.pumpWidget(page(100));
      outer.jumpTo(300);
      intro.jumpTo(600);
      final snapshot = RouteScrollSnapshot.capture([
        outer,
        intro,
        detached,
        null,
      ]);
      outer.jumpTo(0);
      intro.jumpTo(0);
      snapshot.restore();
      expect(outer.offset, 300);
      expect(intro.offset, 600);
      await tester.pumpWidget(page(6));
      await tester.pump();
      snapshot.restore();
      expect(outer.offset, outer.position.maxScrollExtent);
      expect(intro.offset, intro.position.maxScrollExtent);
      await tester.pumpWidget(const SizedBox());
      snapshot.restore();
      expect(tester.takeException(), isNull);
      outer.dispose();
      intro.dispose();
      detached.dispose();
    },
  );
}
