import 'package:PiliPlus/models_new/download/bili_download_entry_info.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';

import 'package:PiliPlus/private/cache_exporter/domain.dart';
import 'package:PiliPlus/private/cache_exporter/export_service.dart';
import 'package:PiliPlus/private/cache_exporter/pili_adapter.dart';
import 'package:PiliPlus/private/cache_exporter/subtitle_provider.dart';

abstract final class CacheExportLauncher {
  static Future<void> open(
    BuildContext context,
    BiliDownloadEntryInfo entry,
  ) async {
    final dto = PiliCacheAdapter.fromEntry(entry);
    final destination = await FilePicker.getDirectoryPath(
      dialogTitle: '选择缓存导出目录',
      lockParentWindow: true,
    );
    if (destination == null || !context.mounted) return;

    final token = CancellationToken();
    final service = CacheExportService(subtitles: const PiliSubtitleProvider());
    ExportProgress progress = const ExportProgress(
      ExportStage.validating,
      0,
      '准备导出…',
    );
    var finished = false;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) {
          if (!finished) {
            finished = true;
            Future<void>(() async {
              try {
                final result = await service.export(
                  entryDirectory: dto.entryDirectory,
                  destinationDirectory: destination,
                  options: const ExportOptions(),
                  cancellation: token,
                  onProgress: (value) {
                    progress = value;
                    if (dialogContext.mounted) setState(() {});
                  },
                );
                if (dialogContext.mounted) Navigator.of(dialogContext).pop();
                final detail = result.warnings.isEmpty
                    ? '导出完成：${result.videoPath}'
                    : '导出完成（有提示）：${result.warnings.join('；')}';
                SmartDialog.showToast(
                  detail,
                  displayTime: const Duration(seconds: 5),
                );
              } on ExportCancelled {
                if (dialogContext.mounted) Navigator.of(dialogContext).pop();
                SmartDialog.showToast('已取消导出');
              } catch (error) {
                if (dialogContext.mounted) Navigator.of(dialogContext).pop();
                SmartDialog.showToast(
                  '导出失败：$error',
                  displayTime: const Duration(seconds: 6),
                );
              }
            });
          }
          return AlertDialog(
            title: const Text('导出缓存'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(progress.message),
                const SizedBox(height: 16),
                LinearProgressIndicator(value: progress.fraction),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  await service.cancel(token);
                },
                child: const Text('取消'),
              ),
            ],
          );
        },
      ),
    );
  }
}
