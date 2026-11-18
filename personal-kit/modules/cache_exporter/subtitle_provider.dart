import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/http/video.dart';
import 'package:PiliPlus/models_new/video/video_play_info/subtitle.dart';
import 'package:PiliPlus/private/cache_exporter/domain.dart';

final class PiliSubtitleProvider implements SubtitleProvider {
  const PiliSubtitleProvider();

  @override
  Future<List<SubtitleAsset>> discover(CacheExportSource source) async {
    final response = await VideoHttp.playInfo(
      aid: source.aid.toString(),
      bvid: source.bvid,
      cid: source.cid,
      epId: source.epId,
    );
    if (response case Success(:final response)) {
      final tracks = response.subtitle?.subtitles ?? const <Subtitle>[];
      final result = <SubtitleAsset>[];
      for (final track in tracks) {
        final url = track.subtitleUrl;
        if (url == null || url.isEmpty) continue;
        final vtt = await VideoHttp.vttSubtitles(url);
        final srt = await VideoHttp.vttSubtitles(url, format: .srt);
        if (vtt == null || srt == null) continue;
        result.add(
          SubtitleAsset(
            language: track.lan,
            label: track.lanDoc ?? track.lan,
            vtt: vtt,
            srt: srt,
          ),
        );
      }
      return result;
    }
    throw ExportFailure('subtitle_discovery_failed', response.toString());
  }
}
