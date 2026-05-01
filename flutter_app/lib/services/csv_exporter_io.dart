import 'dart:io';

Future<String> saveCsvFile(String filename, String contents) async {
  final home = Platform.environment['HOME'] ?? '.';
  final desktop = Directory('$home/Desktop');
  final directory = desktop.existsSync() ? desktop.path : home;
  final file = File('$directory/$filename');
  await file.writeAsString(contents);
  return 'Saved to ${file.path}';
}
