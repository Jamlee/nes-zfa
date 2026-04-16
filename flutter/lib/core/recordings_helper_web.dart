/// Web stub for recordings helper — no filesystem on web.
class RecordingsHelper {
  static Future<List<Map<String, dynamic>>> loadRecordings() async => [];
  static Future<void> deleteRecording(String path) async {}
  static void openFolder(String path) {}
}
