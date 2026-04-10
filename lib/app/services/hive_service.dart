import 'package:hive_flutter/hive_flutter.dart';

import '../../app/services/face_recognition_service.dart';
import '../../app/types/face_pipeline.dart';
import '../../app/services/log_service.dart';

class FaceDatabaseService {
  final Box _hiveBox = Hive.box('face_db');

  // Hàm này chỉ việc đọc ổ cứng, format data, rồi gọi FFI ném xuống C++
  Future<void> loadDatabaseIntoSession(int sessionHandle) async {
    if (_hiveBox.isEmpty) {
      return;
    }

    int count = 0;
    for (var key in _hiveBox.keys) {
      final rawData = _hiveBox.get(key);
      if (rawData is Map) {
        final mapData = Map<String, dynamic>.from(rawData);
        final List<double> vector = List<double>.from(mapData['vector'] ?? []);

        if (vector.length == FaceRecognitionService.outputSize) {
          FaceImagePipelineNative.addFaceToNativeSession(
            sessionHandle: sessionHandle,
            name: key.toString(),
            embedding: vector,
            templateId: mapData['template_id']?.toString() ?? "unknown",
          );
          count++;

          if (count % 100 == 0) {
            await Future.delayed(Duration.zero);
          }
        }
      }
    }

    AppLog.info("✅ Đã load thành công $count khuôn mặt vào C++ Session");
  }
}
