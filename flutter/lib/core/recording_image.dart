/// Platform-conditional GIF image widget for recordings.
///
/// On web: shows placeholder icon.
/// On native: loads GIF from filesystem via [Image.file].

export 'recording_image_web.dart'
    if (dart.library.io) 'recording_image_io.dart';
