library smotion_log;

import 'dart:async';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:logger/logger.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class SmotionLog {
  static final defaultPrinter = PrettyPrinter(
    methodCount: 0,
    errorMethodCount: 15,
    excludeBox: {
      Level.trace: true,
      Level.debug: true,
    },
  );
  static const _logsDirectoryName = "logs";
  static const _fileDefaultName = "log";

  static final SmotionLog _instance = SmotionLog._();

  static SmotionLog get instance => _instance;

  Logger _logger;
  LogPrinter _printer;
  IOSink? _file;

  SmotionLog._()
      : _logger = Logger(printer: defaultPrinter),
        _printer = defaultPrinter;

  set setPrinter(LogPrinter p) {
    _printer = p;
    _logger.close().then((_) => _logger = Logger(printer: _printer));
  }

  void debug(String message, {StackTrace? st}) =>
      _logger.d(message, stackTrace: st);

  void error(String message, [Object? error, StackTrace? stackTrace]) =>
      _logger.e(message, error: error, stackTrace: stackTrace);

  void info(String message) => _logger.i(message);

  void warning(String message) => _logger.w(message);

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
        'Session starts at: ${DateTime.now().toIso8601String()}');

    await _logger.close();
    _logger = Logger(
      printer: _printer,
      filter: ProductionFilter(),
      output: MultiOutput(
        [
          ConsoleOutput(),
          if (Platform.isIOS) _FileLogOutput(_file),
        ],
      ),
    );
  }

  Future<void> closeFileLog() async {
    _writeHeaderToFile(
        'Session closed at: ${DateTime.now().toIso8601String()}');
    await _file?.close();
  }

  Future<void> exportLog([String? zipFileName]) async {
    final String logsDir = await _getLogsDirectoryPath();
    final List<File>? logFiles = await _getAllLogFiles(logsDir);
    if (logFiles == null || logFiles.isEmpty) {
      warning("Exporting logs, directory not exist or empty");
      return;
    }
    final encoder = ZipFileEncoder();
    final String logsArchivePath = '$logsDir/${zipFileName ?? 'all_logs'}.zip';
    encoder.create(logsArchivePath);
    await Future.forEach(logFiles, encoder.addFile);
    encoder.close();
    await Share.shareXFiles([XFile(logsArchivePath)], text: "Skaiscan logs")
        .then((r) {
      info("Share logs result: ${r.status.name}");
      return File(logsArchivePath).delete();
    });
  }

  Future<String> _getLogsDirectoryPath() async {
    final Directory appDocumentsDirectory =
        await getApplicationDocumentsDirectory();
    return '${appDocumentsDirectory.path}/$_logsDirectoryName';
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
