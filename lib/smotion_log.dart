library smotion_log;

import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class SmotionLog {
  static const _logsDirectoryName = "app_logs";
  static const _fileDefaultName = "session";
  static final SmotionLog _instance = SmotionLog._();
  static SmotionLog get instance => _instance;

  static Logger _createLogger({
    LogPrinter? printer,
    LogOutput? output,
    LogFilter? filter,
    Level? level,
  }) =>
      Logger(
        printer: printer ??
            PrettyPrinter(
              methodCount: 0,
              errorMethodCount: 15,
              excludeBox: {
                Level.trace: true,
                Level.debug: true,
              },
            ),
        output: output ?? _CustomConsoleOutput(),
        filter: filter ?? ProductionFilter(),
        level: level ?? Level.trace,
      );

  Logger _logger;
  IOSink? _file;

  SmotionLog._() : _logger = _createLogger();

  void setPrinter(LogPrinter p) async {
    await _logger.close().then((_) => _logger = _createLogger(printer: p));
  }

  void debug(String message, {StackTrace? st}) =>
      _logger.d(message, stackTrace: st);

  void error(String message, [Object? error, StackTrace? stackTrace]) =>
      _logger.e(message, error: error, stackTrace: stackTrace);

  void info(String message) => _logger.i(message);

  void warning(String message) => _logger.w(message);

  void trace(String message) => _logger.t(message);

  /// Call to include logging to file
  Future<void> initFileLog([String fileName = _fileDefaultName]) async {
    _file = await _getLogsDirectoryPath().then(
      (logsDir) {
        final String path = "$logsDir/${DateTime.now()}_$fileName.txt";
        File(path).createSync(recursive: true);
        return File(path).openWrite();
      },
    );
    _writeHeaderToFile(
      'Session starts at: ${DateTime.now().toIso8601String()}',
    );

    await _logger.close();
    _logger = _createLogger(
      output: MultiOutput([_CustomConsoleOutput(), _FileLogOutput(_file)]),
    );
  }

  Future<void> closeFileLog() async {
    _writeHeaderToFile(
      'Session closed at: ${DateTime.now().toIso8601String()}',
    );
    await _file?.close();
  }

  Future<void> exportLog([String? zipFileName, String? shareText]) async {
    final String logsDir = await _getLogsDirectoryPath();
    final List<File>? logFiles = await _getAllLogFiles(logsDir);
    if (logFiles == null || logFiles.isEmpty) {
      warning("Exporting logs, directory not exist or empty");
      return;
    }
    final encoder = ZipFileEncoder();
    final String logsArchivePath =
        '$logsDir/${zipFileName ?? _logsDirectoryName}.zip';
    encoder.create(logsArchivePath);
    await Future.forEach(logFiles, encoder.addFile);
    encoder.close();
    await Share.shareXFiles(
      [XFile(logsArchivePath)],
      text: shareText ?? _logsDirectoryName,
    ).then((r) {
      info("Share logs result: ${r.status.name}");
      return File(logsArchivePath).delete();
    });
  }

  Future<String> _getLogsDirectoryPath([String? dirName]) async {
    final Directory appDocumentsDirectory =
        await getApplicationDocumentsDirectory();
    return '${appDocumentsDirectory.path}/${dirName??_logsDirectoryName}';
  }

  Future<List<File>?> _getAllLogFiles([String? dirPath]) async {
    final Directory logsDirectory =
        Directory(dirPath ?? await _getLogsDirectoryPath());
    if (!(await logsDirectory.exists())) return null;
    return logsDirectory
        .list()
        .toList()
        .then((l) => l.map((e) => File(e.path)).toList());
  }

  void _writeHeaderToFile(String state) {
    _file?.writeln('');
    _file?.writeln(List.filled(100, '=').join());
    _file?.writeln(state);
    _file?.writeln(List.filled(100, '=').join());
    _file?.writeln('');
  }
}

class _FileLogOutput extends LogOutput {
  IOSink? _file;

  _FileLogOutput(this._file);

  @override
  void output(OutputEvent event) {
    for (final String line in event.lines) {
      _file?.writeln("$line\n");
    }
  }
}

class _CustomConsoleOutput extends ConsoleOutput {
  @override
  void output(OutputEvent event) {
    kDebugMode ? event.lines.forEach(developer.log) : super.output(event);
  }
}
