// Conditional export: uses dart:html on web, dart:io on all other platforms.
export 'file_saver_io.dart'
    if (dart.library.html) 'file_saver_web.dart';
