import 'package:PiliPlus/models_new/download/bili_download_entry_info.dart';

final class PiliCacheEntryDto {
  const PiliCacheEntryDto({
    required this.entryDirectory,
    required this.title,
    required this.aid,
    required this.bvid,
    required this.cid,
    this.epId,
  });

  final String entryDirectory;
  final String title;
  final int aid;
  final String bvid;
  final int cid;
  final int? epId;
}

abstract final class PiliCacheAdapter {
  static PiliCacheEntryDto fromEntry(BiliDownloadEntryInfo entry) {
    if (!entry.isCompleted) {
      throw StateError(
        'Only completed PiliPlus cache entries can be exported.',
      );
    }
    return PiliCacheEntryDto(
      entryDirectory: entry.entryDirPath,
      title: entry.showTitle,
      aid: entry.avid,
      bvid: entry.bvid,
      cid: entry.cid,
      epId: entry.ep?.episodeId,
    );
  }
}
