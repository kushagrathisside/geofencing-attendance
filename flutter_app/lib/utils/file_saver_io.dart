import 'dart:io';

Future<String> saveFile(String filename, String content) async {
  final home = Platform.environment['HOME'] ?? '.';
  final path = '$home/Desktop/$filename';
  await File(path).writeAsString(content);
  return path;
}
