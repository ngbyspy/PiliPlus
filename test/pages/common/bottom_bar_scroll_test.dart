import 'dart:io';

import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/pages/common/common_page.dart';
import 'package:PiliPlus/pages/main/controller.dart';
import 'package:PiliPlus/services/account_service.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive_ce/hive.dart';
import 'package:material_ui/material_ui.dart';

class _Shell extends MainController {
  _Shell(this.sync);

  final bool sync;

  @override
  // ignore: must_call_super
  void onInit() {
    if (sync) {
      barOffset = 0.0.obs;
    } else {
      showBottomBar = true.obs;
    }
  }

  @override
  // ignore: must_call_super
  void onClose() {}

  @override
  void setSearchBar() {}
}

class _Account extends AccountService {
  @override
  // ignore: must_call_super
  void onInit() {}
}

class _Feed extends StatefulWidget {
  const _Feed(this.controller, {this.active = true});

  final ScrollController controller;
  final bool active;

  @override
  State<_Feed> createState() => _FeedState();
}

class _FeedState extends CommonPageState<_Feed> {
  @override
  bool get isScrollPageActive => widget.active;

  @override
  Widget build(BuildContext context) => onBuild(
    ListView.builder(
      controller: widget.controller,
      physics: const ClampingScrollPhysics(),
      itemExtent: 80,
      itemCount: 100,
      itemBuilder: (_, index) => Text('内容 $index'),
    ),
  );
}

void main() {
  late Directory storage;
  setUpAll(() async {
    storage = await Directory.systemTemp.createTemp('piliplus-bottom-bar-');
    Hive.init(storage.path);
    GStorage.setting = await Hive.openBox('setting');
  });
  tearDownAll(() async {
    await Hive.close();
    await storage.delete(recursive: true);
  });
  tearDown(Get.reset);

  for (final sync in [false, true]) {
    testWidgets(
      'cached page activation preserves the current bar position (sync=$sync)',
      (tester) async {
        Get.put<AccountService>(_Account());
        final shell = Get.put<MainController>(_Shell(sync));
        final scroll = ScrollController();
        final active = ValueNotifier(true);
        await tester.pumpWidget(
          MaterialApp(
            home: ValueListenableBuilder<bool>(
              valueListenable: active,
              child: _Feed(scroll),
              builder: (_, enabled, child) =>
                  TickerMode(enabled: enabled, child: child!),
            ),
          ),
        );
        if (sync) {
          shell.barOffset!.value = Style.topBarHeight * .55;
        } else {
          shell.showBottomBar!.value = false;
        }
        active.value = false;
        await tester.pump();
        active.value = true;
        await tester.pumpAndSettle();
        if (sync) {
          expect(shell.barOffset!.value, Style.topBarHeight * .55);
        } else {
          expect(shell.showBottomBar!.value, isFalse);
        }
        await tester.pumpWidget(const SizedBox.shrink());
        scroll.dispose();
        active.dispose();
      },
    );

    testWidgets('small scroll changes follow the selected mode (sync=$sync)', (
      tester,
    ) async {
      Get.put<AccountService>(_Account());
      final shell = Get.put<MainController>(_Shell(sync));
      final scroll = ScrollController();
      await tester.pumpWidget(MaterialApp(home: _Feed(scroll)));
      scroll.jumpTo(200);
      await tester.pumpAndSettle();
      final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
      void direction(ScrollDirection value) => UserScrollNotification(
        metrics: scroll.position,
        context: scrollable.context,
        direction: value,
      ).dispatch(scrollable.context);
      void update(double delta, {bool dragged = true}) =>
          ScrollUpdateNotification(
            metrics: scroll.position,
            context: scrollable.context,
            scrollDelta: delta,
            dragDetails: dragged
                ? DragUpdateDetails(
                    globalPosition: Offset.zero,
                    delta: Offset(0, -delta),
                  )
                : null,
          ).dispatch(scrollable.context);

      direction(ScrollDirection.reverse);
      update(7);
      if (sync) {
        expect(shell.barOffset!.value, 7);
        update(11);
        expect(shell.barOffset!.value, 18);
      } else {
        expect(shell.showBottomBar!.value, isFalse);
      }
      direction(ScrollDirection.forward);
      update(-3);
      ScrollEndNotification(
        metrics: scroll.position,
        context: scrollable.context,
      ).dispatch(scrollable.context);
      direction(ScrollDirection.idle);
      await tester.pumpAndSettle();
      if (sync) {
        expect(shell.barOffset!.value, 15);
        update(40, dragged: false);
        await tester.pumpAndSettle();
        expect(shell.barOffset!.value, 15);
      } else {
        expect(shell.showBottomBar!.value, isTrue);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      scroll.dispose();
    });
  }

  testWidgets('user overscroll changes the offset without snapping open', (
    tester,
  ) async {
    Get.put<AccountService>(_Account());
    final shell = Get.put<MainController>(_Shell(true));
    final scroll = ScrollController();
    await tester.pumpWidget(MaterialApp(home: _Feed(scroll)));
    shell.barOffset!.value = Style.topBarHeight / 2;
    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    OverscrollNotification(
      metrics: scroll.position,
      context: scrollable.context,
      overscroll: -4,
      dragDetails: DragUpdateDetails(globalPosition: Offset.zero),
    ).dispatch(scrollable.context);
    ScrollEndNotification(
      metrics: scroll.position,
      context: scrollable.context,
    ).dispatch(scrollable.context);
    await tester.pumpAndSettle();
    expect(shell.barOffset!.value, Style.topBarHeight / 2 - 4);
    await tester.pumpWidget(const SizedBox.shrink());
    scroll.dispose();
  });

  testWidgets('an inactive feed cannot change the shared bar', (tester) async {
    Get.put<AccountService>(_Account());
    final shell = Get.put<MainController>(_Shell(false));
    final scroll = ScrollController();
    await tester.pumpWidget(MaterialApp(home: _Feed(scroll, active: false)));
    await tester.drag(find.byType(ListView), const Offset(0, -180));
    await tester.pumpAndSettle();
    expect(scroll.offset, greaterThan(0));
    expect(shell.showBottomBar!.value, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    scroll.dispose();
  });

  testWidgets('a fling hitting the trailing edge cannot hide the bar', (
    tester,
  ) async {
    Get.put<AccountService>(_Account());
    final shell = Get.put<MainController>(_Shell(true));
    final scroll = ScrollController();
    await tester.pumpWidget(MaterialApp(home: _Feed(scroll)));
    scroll.jumpTo(scroll.position.maxScrollExtent);
    await tester.pumpAndSettle();

    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    OverscrollNotification(
      metrics: scroll.position,
      context: scrollable.context,
      overscroll: 80,
      velocity: 2400,
    ).dispatch(scrollable.context);
    expect(shell.barOffset!.value, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    scroll.dispose();
  });
}
