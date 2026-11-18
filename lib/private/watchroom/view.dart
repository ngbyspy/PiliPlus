import 'package:PiliPlus/utils/accounts.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

import 'model.dart';
import 'piliplus_adapter.dart';

class WatchroomPage extends StatefulWidget {
  final String? link;
  final int? episodeId, seasonId;
  final bool embedded;
  const WatchroomPage({
    super.key,
    this.link,
    this.episodeId,
    this.seasonId,
    this.embedded = false,
  });
  @override
  State<WatchroomPage> createState() => _WatchroomPageState();
}

class _WatchroomPageState extends State<WatchroomPage> {
  final adapter = WatchroomAdapter.instance;
  late final invite = TextEditingController(text: widget.link);
  late final episode = TextEditingController(
    text: widget.episodeId?.toString(),
  );
  final message = TextEditingController();
  final scroll = ScrollController();
  bool working = false;
  String problem = '';

  Future<void> login() async {
    await Get.toNamed<void>('/loginPage');
    if (mounted) setState(() {});
  }

  Future<void> copyInvitation() => run(() async {
    final session = adapter.session;
    if (session == null) throw StateError('请先加入放映室');
    final invitation = await session.invitationForShare();
    await Clipboard.setData(ClipboardData(text: '${invitation.mobileUri}'));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('邀请链接已复制')),
      );
    }
  });

  @override
  void dispose() {
    invite.dispose();
    episode.dispose();
    message.dispose();
    scroll.dispose();
    super.dispose();
  }

  Future<void> run(Future<void> Function() action, {bool play = false}) async {
    if (working) return;
    setState(() {
      working = true;
      problem = '';
    });
    try {
      await action();
      if (mounted && play) {
        if (widget.embedded) Navigator.of(context).pop();
        await adapter.openPlayer();
      }
    } catch (e) {
      if (mounted)
        setState(() {
          problem = '$e';
        });
    } finally {
      if (mounted)
        setState(() {
          working = false;
        });
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: adapter,
    builder: (context, _) {
      final session = adapter.session, room = session?.room;
      return Scaffold(
        appBar: AppBar(
          title: const Text('B站放映室'),
          actions: [
            if (room != null)
              IconButton(
                tooltip: '复制邀请链接',
                icon: const Icon(Icons.link),
                onPressed: working ? null : copyInvitation,
              ),
          ],
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: room == null
                ? ListView(
                    children: [
                      const SizedBox(height: 12),
                      const Text(
                        '与 B 站官方客户端、电脑网页进入同一个房间，使用 PiliPlus 原生播放器一起看。',
                      ),
                      const SizedBox(height: 16),
                      if (!Accounts.main.isLogin)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: FilledButton.tonal(
                            onPressed: login,
                            child: const Text('登录 PiliPlus 主账号'),
                          ),
                        ),
                      TextField(
                        controller: invite,
                        key: const ValueKey('watchroom-invite'),
                        minLines: 1,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: '邀请链接或房间号',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: working
                            ? null
                            : () => run(
                                () => adapter.join(invite.text),
                                play: true,
                              ),
                        icon: const Icon(Icons.group_add_outlined),
                        label: const Text('加入官方放映室'),
                      ),
                      const SizedBox(height: 12),
                      ExpansionTile(
                        title: const Text('创建放映室'),
                        initiallyExpanded: widget.episodeId != null,
                        children: [
                          TextField(
                            controller: episode,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: '剧集 EP 号',
                              hintText: '例如 373924',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 8),
                          FilledButton.tonal(
                            onPressed: working
                                ? null
                                : () => run(
                                    () => adapter.create(
                                      episode: roomInt(episode.text),
                                      season: widget.seasonId,
                                    ),
                                    play: true,
                                  ),
                            child: const Text('创建并邀请好友'),
                          ),
                        ],
                      ),
                      if (working) const LinearProgressIndicator(),
                      if (problem.isNotEmpty ||
                          (session?.error.isNotEmpty ?? false))
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: SelectableText(
                            problem.isNotEmpty ? problem : session!.error,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '房间 ${room.roomId} · ${session!.connection}',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        room.members
                            .map(
                              (m) =>
                                  '${m.mid == room.ownerId ? '房主：' : ''}${m.name}',
                            )
                            .join(' · '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.tonalIcon(
                              onPressed: () => run(() async {
                                if (widget.embedded)
                                  Navigator.of(context).pop();
                                await adapter.openPlayer();
                              }),
                              icon: const Icon(Icons.play_arrow),
                              label: Text(
                                session.playerAttached
                                    ? '正在原生播放器播放'
                                    : '打开原生播放器',
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: '重新同步',
                            onPressed: () => run(session.refresh),
                            icon: const Icon(Icons.sync),
                          ),
                          IconButton(
                            tooltip: '退出房间',
                            onPressed: working
                                ? null
                                : () => run(session.leave),
                            icon: const Icon(Icons.logout),
                          ),
                        ],
                      ),
                      OutlinedButton.icon(
                        onPressed: working ? null : copyInvitation,
                        icon: const Icon(Icons.person_add_alt_1_outlined),
                        label: const Text('邀请好友'),
                      ),
                      if (session.isOwner)
                        SwitchListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: const Text('同步我的播放操作'),
                          subtitle: const Text('开启后，播放、暂停、拖动和换集会同步给房间成员'),
                          value: session.controlRoom,
                          onChanged: working
                              ? null
                              : (value) => run(() => session.setControl(value)),
                        ),
                      if (!session.canControl)
                        SwitchListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: const Text('跟随房主'),
                          value: session.followHost,
                          onChanged: (value) =>
                              run(() => session.setFollow(value)),
                        ),
                      if (problem.isNotEmpty || session.error.isNotEmpty)
                        Text(
                          problem.isNotEmpty ? problem : session.error,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                          maxLines: 3,
                        ),
                      const Divider(),
                      Expanded(
                        child: session.messages.isEmpty
                            ? const Center(child: Text('房间文字聊天'))
                            : ListView.builder(
                                controller: scroll,
                                reverse: true,
                                itemCount: session.messages.length,
                                itemBuilder: (context, index) {
                                  final item =
                                      session.messages[session.messages.length -
                                          index -
                                          1];
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 5,
                                    ),
                                    child: Text.rich(
                                      TextSpan(
                                        children: [
                                          TextSpan(
                                            text: '${item.author}：',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          TextSpan(text: item.text),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                      Padding(
                        padding: EdgeInsets.only(
                          bottom: MediaQuery.viewInsetsOf(context).bottom > 0
                              ? 4
                              : 12,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: message,
                                maxLength: 233,
                                minLines: 1,
                                maxLines: 3,
                                decoration: const InputDecoration(
                                  hintText: '发送房间文字消息',
                                  counterText: '',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: '发送',
                              onPressed: working
                                  ? null
                                  : () => run(() async {
                                      final text = message.text;
                                      await session.sendText(text);
                                      if (mounted && message.text == text)
                                        message.clear();
                                    }),
                              icon: const Icon(Icons.send),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      );
    },
  );
}
