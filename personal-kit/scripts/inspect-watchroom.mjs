// Read only this debug app's synchronization state through its local Dart VM
// service. Cookies, invitation tokens and media URLs are never evaluated or
// printed. The temporary localhost ADB forward is removed on completion.
import { execFileSync } from 'node:child_process';

const adb = (...args) => {
  try {
    return execFileSync('adb', args, {
      encoding: 'utf8', windowsHide: true, timeout: 15000, maxBuffer: 4 * 1024 * 1024,
    });
  } catch {
    // Do not let Node print an error object's raw logcat stdout.
    throw new Error('The required ADB operation failed. Check the device connection.');
  }
};
const packageName = 'com.example.piliplus.debug';
const attachedUrl = process.argv.slice(2).find(argument => argument.startsWith('--vm-url='))?.slice('--vm-url='.length);
const checkShare = process.argv.includes('--check-share');
const probeArgument = process.argv.slice(2).find(argument => argument.startsWith('--room-info='));
const probeRoom = probeArgument?.slice('--room-info='.length);
if (probeRoom && !/^[1-9]\d*$/.test(probeRoom)) throw new Error('A numeric room ID is required.');
const probeSeason = process.argv.slice(2).find(argument => argument.startsWith('--season-id='))?.slice('--season-id='.length);
const probeEpisode = process.argv.slice(2).find(argument => argument.startsWith('--episode-id='))?.slice('--episode-id='.length);
if ((probeSeason || probeEpisode) && (!/^[1-9]\d*$/.test(probeSeason ?? '') || !/^[1-9]\d*$/.test(probeEpisode ?? ''))) {
  throw new Error('Both numeric season and episode IDs are required.');
}
const probeInvitation = Boolean(probeRoom && probeSeason && probeEpisode);
const expectedArgument = process.argv.slice(2).find(argument => argument.startsWith('--expect-inviter='));
const expectedInviter = expectedArgument?.slice('--expect-inviter='.length);
if (expectedInviter && !/^[1-9]\d*$/.test(expectedInviter)) throw new Error('A numeric inviter ID is required.');
const accountMatch = expectedInviter ? `Accounts.main.mid == ${expectedInviter}` : 'null';
const pid = adb('shell', 'pidof', packageName).trim();
if (!/^\d+$/.test(pid)) throw new Error('The watchroom debug app is not running.');
let advertisedUrl;
try {
  const endpoint = JSON.parse(adb('shell', 'run-as', packageName, 'cat', 'cache/watchroom-vm-service.json'));
  if (String(endpoint.pid) === pid) advertisedUrl = endpoint.url;
} catch { /* Older builds can still advertise through logcat. */ }
if (!advertisedUrl) {
  const logs = adb('logcat', '-d', '--pid=' + pid, '-t', '1500');
  const matches = [...logs.matchAll(/(?:Dart VM service is listening on|Observatory listening on)\s+(http:\/\/127\.0\.0\.1:\d+\/[^\s]*)/g)];
  advertisedUrl = matches.at(-1)?.[1];
}
if (!advertisedUrl) throw new Error('Open the watchroom page in the latest debug build before inspecting.');
const deviceUrl = new URL(advertisedUrl);
if (deviceUrl.protocol !== 'http:' || deviceUrl.hostname !== '127.0.0.1' || !/^\d+$/.test(deviceUrl.port)) {
  throw new Error('The debug endpoint must be a device-local HTTP service.');
}
const port = adb('forward', 'tcp:0', 'tcp:' + deviceUrl.port).trim();
if (!/^\d+$/.test(port)) throw new Error('ADB did not allocate a localhost debugging port.');
let socket;
try {
  const socketUrl = new URL(attachedUrl ?? ('http://127.0.0.1:' + port + deviceUrl.pathname));
  if (socketUrl.protocol !== 'http:' || socketUrl.hostname !== '127.0.0.1' || socketUrl.username || socketUrl.password) {
    throw new Error('The attached VM endpoint must be a local HTTP service.');
  }
  socket = new WebSocket('ws://' + socketUrl.host + socketUrl.pathname + 'ws');
  await new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('Local Dart VM connection timed out.')), 10000);
    socket.addEventListener('open', () => { clearTimeout(timer); resolve(); }, { once: true });
    socket.addEventListener('error', () => { clearTimeout(timer); reject(new Error('Cannot connect to the local Dart VM.')); }, { once: true });
  });
  const requests = new Map();
  let sequence = 0;
  socket.addEventListener('message', event => {
    const response = JSON.parse(String(event.data));
    const pending = requests.get(response.id);
    if (!pending) return;
    requests.delete(response.id); clearTimeout(pending.timer);
    if (response.error) pending.reject(new Error(
      response.error.code === 113
        ? response.error.data?.details ?? response.error.message
        : response.error.message,
    ));
    else pending.resolve(response.result);
  });
  function rpc(method, params = {}) {
    return new Promise((resolve, reject) => {
      const id = String(++sequence);
      const timer = setTimeout(() => { requests.delete(id); reject(new Error(method + ' timed out.')); }, 10000);
      requests.set(id, { resolve, reject, timer });
      socket.send(JSON.stringify({ jsonrpc: '2.0', id, method, params }));
    });
  }
  const vm = await rpc('getVM');
  const main = vm.isolates.find(isolate => isolate.name === 'main');
  if (!main) throw new Error('The main app isolate is not available.');
  const isolate = await rpc('getIsolate', { isolateId: main.id });
  const library = isolate.libraries.find(value => value.uri === 'package:PiliPlus/private/watchroom/piliplus_adapter.dart');
  if (!library) throw new Error('The running app does not include the watchroom adapter.');
  const expression = (checkShare ? `(() async {
    try {
      final session = WatchroomAdapter.instance.session;
      if (session == null || ${probeRoom ? `session.room?.roomId != ${probeRoom}` : '!session.active'}) throw StateError('当前房间不可用');
      final invite = await session.invitationForShare();
      return jsonEncode({'shareReady': true, 'roomId': invite.roomId, 'episodeId': invite.episodeId, 'shareHasToken': invite.token?.isNotEmpty ?? false, 'shareHasInviter': invite.inviter?.isNotEmpty ?? false});
    } catch (e) { return jsonEncode({'shareReady': false, 'error': e.toString()}); }
  })()` : probeRoom ? `(() async {
    try {
      final response = await PiliRoomTransport(Accounts.main).call('${probeInvitation ? 'pgc/view/web/freya/season' : 'pgc/freya/web/room/info'}', parameters: {'room_id': ${probeRoom}, 'platform': 'web'${probeInvitation ? `, 'season_id': ${probeSeason}, 'ep_id': ${probeEpisode}` : ''}});
      final data = ${probeInvitation ? "roomMap(response['room_info'])" : 'response'};
      return jsonEncode({
        'accountMatchesInviter': ${accountMatch},
        'infoKeys': data.keys.toList(),
        'roomId': roomInt(data['room_id']),
        'isOpen': data['is_open'],
        'isOwner': roomInt(data['mid']) == Accounts.main.mid,
        'episodeId': roomInt(data['episode_id']),
        'statusKeys': roomMap(data['status']).keys.toList(),
        'shareHasToken': Uri.tryParse(data['share_url']?.toString() ?? '')?.queryParameters.containsKey('token') ?? false
        ,'shareHasInviter': Uri.tryParse(data['share_url']?.toString() ?? '')?.queryParameters.containsKey('invitemid') ?? false
      });
    } catch (e) { return jsonEncode({'accountMatchesInviter': ${accountMatch}, 'roomInfoError': e.toString()}); }
  })()` : `jsonEncode({
    'loggedIn': Accounts.main.isLogin,
    'accountMatchesInviter': ${accountMatch},
    'joined': WatchroomAdapter.instance.session?.active ?? false,
    'connection': WatchroomAdapter.instance.session?.connection,
    'roomId': WatchroomAdapter.instance.session?.room?.roomId,
    'episodeId': WatchroomAdapter.instance.session?.room?.episodeId,
    'roomStatus': WatchroomAdapter.instance.session?.room?.status,
    'roomPositionMs': WatchroomAdapter.instance.session?.room?.targetAt(DateTime.now()).inMilliseconds,
    'playerPositionMs': WatchroomAdapter.instance._boundPlayer?.positionInMilliseconds,
    'playerPlaying': WatchroomAdapter.instance._boundPlayer?.playerStatus.isPlaying,
    'nativePlaying': WatchroomAdapter.instance._boundPlayer?.videoPlayerController?.state.playing,
    'playerProcessing': WatchroomAdapter.instance._boundPlayer?.processing,
    'boundEpisodeId': WatchroomAdapter.instance.session?._player?.episodeId,
    'following': WatchroomAdapter.instance.session?.followHost,
    'controlling': WatchroomAdapter.instance.session?.canControl,
    'playerAttached': WatchroomAdapter.instance.session?.playerAttached,
    'lastApiPath': (WatchroomAdapter.instance.session?.transport as PiliRoomTransport?)?.lastPath,
    'lastApiCode': (WatchroomAdapter.instance.session?.transport as PiliRoomTransport?)?.lastCode,
    'lastApiHadInviteToken': (WatchroomAdapter.instance.session?.transport as PiliRoomTransport?)?.lastHadInviteToken,
    'lastProgressStatus': (WatchroomAdapter.instance.session?.transport as PiliRoomTransport?)?.lastProgressStatus,
    'lastProgressSeconds': (WatchroomAdapter.instance.session?.transport as PiliRoomTransport?)?.lastProgressSeconds,
    'lastProgressCode': (WatchroomAdapter.instance.session?.transport as PiliRoomTransport?)?.lastProgressCode,
    'error': WatchroomAdapter.instance.session?.error
  })`).replace(/\s*\n\s*/g, ' ');
  let value = await rpc('evaluate', { isolateId: main.id, targetId: library.id, expression, disableBreakpoints: true });
  if (probeRoom || checkShare) {
    for (let attempt = 0; value.kind !== 'String' && attempt < 100; attempt++) {
      const future = await rpc('getObject', { isolateId: main.id, objectId: value.id });
      const result = future.fields?.find(field => field.decl?.name === '_resultOrListeners')?.value;
      if (result?.kind === 'String') { value = result; break; }
      await new Promise(resolve => setTimeout(resolve, 100));
    }
  }
  if (value.kind !== 'String') throw new Error('The debug state expression did not return JSON.');
  if (value.valueAsStringIsTruncated) {
    value = await rpc('getObject', { isolateId: main.id, objectId: value.id, offset: 0, count: 8192 });
  }
  const state = JSON.parse(value.valueAsString);
  console.log(JSON.stringify(state, null, 2));
} finally {
  socket?.close();
  adb('forward', '--remove', 'tcp:' + port);
}
