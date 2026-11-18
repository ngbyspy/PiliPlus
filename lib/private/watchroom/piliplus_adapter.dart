import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io' show File, Platform, pid;

import 'package:PiliPlus/http/init.dart';
import 'package:PiliPlus/http/search.dart';
import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/accounts/account.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';

import 'model.dart';
import 'links.dart';
import 'session.dart';
import 'view.dart';

class PiliRoomTransport implements RoomTransport {
  final Account account;
  String? lastPath;
  int? lastCode;
  bool lastHadInviteToken = false;
  int? lastProgressStatus, lastProgressSeconds, lastProgressCode;
  PiliRoomTransport(this.account);
  @override
  Future<Map<String, dynamic>> call(
    String path, {
    bool post = false,
    Map<String, dynamic> parameters = const {},
  }) async {
    if (!identical(Accounts.main, account) || !account.isLogin) {
      throw const RoomApiException(-101, '账号已切换，请重新加入放映室');
    }
    final params = <String, dynamic>{
      ...parameters,
      if (post || path == 'pgc/view/web/freya/season') 'csrf': account.csrf,
    };
    if (params['content'] is Map)
      params['content'] = jsonEncode(params['content']);
    lastPath = path;
    lastCode = null;
    lastHadInviteToken = params['token']?.toString().isNotEmpty ?? false;
    final isProgress = path == 'pgc/freya/web/room/modify/progress';
    if (isProgress) {
      lastProgressStatus = roomInt(params['status']);
      lastProgressSeconds = roomInt(params['progress']);
      lastProgressCode = null;
    }
    try {
      final response = await Request.dio.request<dynamic>(
        'https://api.bilibili.com/$path',
        queryParameters: post ? null : params,
        data: post ? params : null,
        options: Options(
          method: post ? 'POST' : 'GET',
          contentType: Headers.formUrlEncodedContentType,
          headers: const {
            'referer': 'https://www.bilibili.com/',
            'origin': 'https://www.bilibili.com',
            'user-agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36',
          },
          extra: {'account': account},
        ),
      );
      final json = roomMap(response.data);
      final code = roomInt(json['code'], -1);
      lastCode = code;
      if (isProgress) lastProgressCode = code;
      if (code != 0)
        throw RoomApiException(code, '${json['message'] ?? '房间请求失败'}');
      return roomMap(json['data']);
    } on DioException {
      throw const RoomApiException(-1, '房间网络请求失败，请检查网络后重试');
    }
  }
}

/// The only adapter allowed to depend on PiliPlus account and player internals.
/// The protocol/session module communicates exclusively through primitive DTOs
/// and playback callbacks, so Android, iPadOS and Windows share the same core.
class WatchroomAdapter extends ChangeNotifier with WidgetsBindingObserver {
  static final instance = WatchroomAdapter._();
  RoomSession? session;
  Account? _account;
  StreamSubscription<void>? _subscription;
  PlPlayerController? _boundPlayer;
  String? _boundTag;
  WatchroomAdapter._() {
    WidgetsBinding.instance.addObserver(this);
    if (kDebugMode && Platform.isAndroid) unawaited(_saveDebugEndpoint());
  }

  // Some devices omit the VM announcement from logcat. Keep only its local
  // endpoint in this debug app's private cache so ADB can attach without
  // reading account files or changing the device's logging configuration.
  Future<void> _saveDebugEndpoint() async {
    try {
      final info = await developer.Service.getInfo();
      if (info.serverUri == null) return;
      final cache = await getTemporaryDirectory();
      await File('${cache.path}/watchroom-vm-service.json').writeAsString(
        jsonEncode({'pid': pid, 'url': '${info.serverUri}'}),
      );
    } catch (_) {
      // Diagnostics must never prevent the actual room from opening.
    }
  }

  Future<RoomSession> _ensureSession() async {
    final account = Accounts.main;
    if (!account.isLogin)
      throw const RoomApiException(-101, '请先登录 PiliPlus 主账号');
    if (!identical(_account, account)) {
      await session?.leave();
      await _subscription?.cancel();
      _account = account;
      session = RoomSession(
        transport: PiliRoomTransport(account),
        mid: account.mid,
        buvid: _webBuvid(account),
        currentBuvid: () => _webBuvid(account),
        openEpisode: (season, episode) => openPlayer(replace: true),
      );
      _subscription = session!.changes.listen((_) {
        notifyListeners();
      });
    }
    return session!;
  }

  String _webBuvid(Account account) {
    final value = account.cookieJar
        .toList()
        .where((cookie) => cookie.name == 'buvid3')
        .firstOrNull
        ?.value;
    if (value == null || value.isEmpty)
      throw const RoomApiException(-101, '网页设备标识缺失，请重新登录');
    return value;
  }

  Future<void> join(String text) async {
    final invite = await const RoomLinkResolver().resolve(text);
    await (await _ensureSession()).join(invite);
  }

  Future<void> create({required int episode, int? season}) async {
    final current = await _ensureSession();
    if (season == null || season <= 0) {
      final result = await SearchHttp.pgcInfo(epId: episode);
      season = result.dataOrNull?.seasonId;
      if (season == null) throw StateError(result.toString());
    }
    await current.create(season, episode);
  }

  static void open({String? link, int? episodeId, int? seasonId}) {
    Get.to<void>(
      () => WatchroomPage(link: link, episodeId: episodeId, seasonId: seasonId),
    );
  }

  void showPanel(BuildContext context, {int? episodeId, int? seasonId}) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => SizedBox(
        height: MediaQuery.sizeOf(context).height * .83,
        child: WatchroomPage(
          embedded: true,
          episodeId: episodeId,
          seasonId: seasonId,
        ),
      ),
    );
  }

  Widget playerButton(BuildContext context, {int? episodeId, int? seasonId}) =>
      IconButton(
        tooltip: 'B站放映室',
        icon: const Icon(Icons.groups_outlined, color: Colors.white, size: 20),
        onPressed: () =>
            showPanel(context, episodeId: episodeId, seasonId: seasonId),
      );

  bool shouldInitialize(int? episode) => session?.playbackFor(episode) != null;
  Duration? startPosition(int? episode) =>
      session?.playbackFor(episode)?.position;
  bool? initialPlaying(int? episode) => session?.playbackFor(episode)?.playing;

  Future<void> openPlayer({bool replace = false}) async {
    final current = session, snapshot = session?.room;
    if (snapshot == null || current == null) return;
    if (current.playerAttached && !replace) return;
    await PageUtils.viewPgc(
      seasonId: snapshot.seasonId,
      epId: snapshot.episodeId,
      progress: snapshot.targetAt(DateTime.now()).inMilliseconds,
      off: replace && Get.currentRoute == '/videoV',
    );
  }

  void suspend(String identity) {
    if (_boundTag == identity) {
      session?.unbindPlayer(identity);
      _boundTag = null;
      _boundPlayer = null;
    }
  }

  void bind({
    required String identity,
    required int? episodeId,
    required int? seasonId,
    required PlPlayerController player,
  }) {
    final current = session;
    if (current == null ||
        !current.active ||
        episodeId == null ||
        seasonId == null)
      return;
    _boundTag = identity;
    _boundPlayer = player;
    unawaited(
      current
          .bindPlayer(
            RoomPlayer(
              identity: identity,
              episodeId: episodeId,
              seasonId: seasonId,
              position: () =>
                  Duration(milliseconds: player.positionInMilliseconds),
              playing: () =>
                  player.videoPlayerController?.state.playing ??
                  player.playerStatus.isPlaying,
              play: () => player.play(),
              pause: () => player.pause(),
              seek: player.seekTo,
            ),
          )
          .catchError((Object _) {}),
    );
  }

  void observe(PlPlayerController player, String action) {
    if (identical(player, _boundPlayer)) session?.observeLocal(action);
  }

  void observeNativeState(PlPlayerController player) {
    if (identical(player, _boundPlayer) && !player.processing) {
      session?.observeHostPlaybackState();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed)
      unawaited(session?.refresh() ?? Future<void>.value());
  }
}
