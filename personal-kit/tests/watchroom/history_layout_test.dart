import 'package:PiliPlus/models_new/history/history.dart';
import 'package:PiliPlus/models_new/history/list.dart';
import 'package:PiliPlus/pages/common/multi_select/base.dart';
import 'package:PiliPlus/pages/history/widgets/item.dart';
import 'package:PiliPlus/private/watchroom/history_layout.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

class UnusedSelection implements MultiSelectBase {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final scale in [1.0, 1.3, 2.0]) {
    testWidgets(
      'history long PGC title and subtitle fit at text scale $scale',
      (tester) async {
        final item = HistoryItemModel(
          history: History(business: 'pgc'),
          title: 'Re：从零开始的异世界生活 第二季 后半',
          showTitle: '第15话 奥托·苏文/相信的理由',
          authorName: '番剧作者',
          videos: 1,
          viewAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        );
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: Builder(
                builder: (context) => Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: 390,
                    height: historyRowExtent(context),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        children: [
                          const SizedBox(width: 180),
                          HistoryItem(
                            item: item,
                            ctr: UnusedSelection(),
                            onDelete: (_, _) {},
                          ).content(Theme.of(context)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        expect(find.text(item.showTitle!), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
