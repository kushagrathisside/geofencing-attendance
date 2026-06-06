// ignore: avoid_web_libraries_in_flutter
// dart:html is deprecated in favour of package:web but still works in Flutter 3.x.
// Migrate to package:web + dart:js_interop when upgrading to Flutter 4.
import 'dart:html' as html;

Future<String> saveFile(String filename, String content) async {
  final blob = html.Blob([content], 'text/csv');
  final url  = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..click();
  html.Url.revokeObjectUrl(url);
  return filename;
}
