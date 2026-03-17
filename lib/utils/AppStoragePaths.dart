import 'dart:io';

import 'package:path_provider/path_provider.dart';

class AppStoragePaths {
  static bool _didMigrateLegacyFiles = false;

  static bool get _usesDesktopStorage =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  static Future<Directory> _getStorageDirectory() async {
    final directory = _usesDesktopStorage
        ? await getApplicationSupportDirectory()
        : await getApplicationDocumentsDirectory();

    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    return directory;
  }

  static Future<void> _migrateLegacyFiles() async {
    if (_didMigrateLegacyFiles || !_usesDesktopStorage) {
      return;
    }

    final legacyDirectory = await getApplicationDocumentsDirectory();
    final targetDirectory = await _getStorageDirectory();

    final fileNames = ['linkup_config.json', 'error.log'];
    for (final fileName in fileNames) {
      final legacyFile = File('${legacyDirectory.path}/$fileName');
      final targetFile = File('${targetDirectory.path}/$fileName');

      if (await targetFile.exists() || !await legacyFile.exists()) {
        continue;
      }

      await legacyFile.copy(targetFile.path);
    }

    _didMigrateLegacyFiles = true;
  }

  static Future<File> getFile(String fileName) async {
    await _migrateLegacyFiles();
    final directory = await _getStorageDirectory();
    return File('${directory.path}/$fileName');
  }
}
