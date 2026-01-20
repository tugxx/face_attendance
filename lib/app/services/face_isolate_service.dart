import 'dart:async';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import '../../app/types/face_progress.dart';

class FaceIsolateService {
  late Isolate _isolate;
  late SendPort _sendPort;
  final _responseStream = StreamController<dynamic>.broadcast();
  bool _isReady = false;

  // Dùng Map để lưu các Completer đang chờ, Key là ID
  final Map<int, Completer<List<double>?>> _pendingRequests = {};
  int _nextRequestId = 0;

  // Khởi tạo Isolate (Chạy 1 lần duy nhất)
  Future<void> start() async {
    final receivePort = ReceivePort();

    // Spawn Isolate
    _isolate = await Isolate.spawn(_isolateEntryPoint, receivePort.sendPort);

    // Lắng nghe port
    receivePort.listen((message) {
      if (message is SendPort) {
        _sendPort = message;
        _isReady = true;
        debugPrint("✅ FaceIsolateService: Worker Started!");
      } else if (message is List) {
        // Message trả về: [RequestId, ResultList]
        int reqId = message[0];
        List<double>? result = message[1] as List<double>?;

        // Tìm và complete đúng request
        if (_pendingRequests.containsKey(reqId)) {
          _pendingRequests[reqId]?.complete(result);
          _pendingRequests.remove(reqId);
        }
      }
    });
  }

  // --- HÀM 1: CROP NHẬN DIỆN (112x112) ---
  Future<List<double>?> processInIsolate(
    Uint8List yuvBytes,
    int w,
    int h,
    Face face,
    int rot,
  ) async {
    return _sendRequest(yuvBytes, w, h, face, rot, 0); // Type 0
  }

  // --- HÀM 2: CROP ANTI-SPOOF (80x80) ---
  Future<List<double>?> processAntiSpoofInIsolate(
    Uint8List yuvBytes,
    int w,
    int h,
    Face face,
    int rot,
  ) async {
    return _sendRequest(yuvBytes, w, h, face, rot, 1); // Type 1
  }

  Future<List<double>?> _sendRequest(
    Uint8List yuvBytes,
    int width,
    int height,
    Face face,
    int rotation,
    int type,
  ) async {
    if (!_isReady) return null;

    final completer = Completer<List<double>?>();
    int reqId = _nextRequestId++;
    _pendingRequests[reqId] = completer;

    final landmarksData = _extractLandmarks(face);
    if (landmarksData == null) {
      _pendingRequests.remove(reqId);
      return null;
    }

    _sendPort.send([
      reqId,
      yuvBytes,
      width,
      height,
      landmarksData,
      rotation,
      type, // Thêm type vào cuối
    ]);

    final result = await completer.future;
    return result;
  }

  // Hủy Isolate khi thoát app
  void dispose() {
    _isolate.kill();
    _responseStream.close();
  }

  // ----------------------------------------------------------------
  // LOGIC TRONG ISOLATE CON (WORKER)
  // ----------------------------------------------------------------
  static void _isolateEntryPoint(SendPort mainSendPort) {
    final port = ReceivePort();
    mainSendPort.send(port.sendPort); // Gửi cổng của mình cho Main

    // Load thư viện C++ 1 LẦN DUY NHẤT TẠI ĐÂY
    FaceProcessorNative.init();

    port.listen((message) {
      if (message is List) {
        int reqId = message[0]; // Nhận ID
        try {
          final Uint8List bytes = message[1];
          final int width = message[2];
          final int height = message[3];
          final List<double> landmarks = message[4]; // Nhận list landmarks
          final int rotation = message[5];
          final int type = message[6];

          List<double>? result;

          if (type == 0) {
            // Gọi hàm 112x112 (Recog)
            result = FaceProcessorNative.processWithRawLandmarks(
              bytes,
              width,
              height,
              landmarks,
              rotation,
            );
          } else {
            // Gọi hàm 80x80 (Spoof) - Cần viết thêm hàm này trong FaceProcessorNative
            // Hoặc dùng hàm chung nếu C++ hỗ trợ tham số size
            result = FaceProcessorNative.processAntiSpoofRaw(
              bytes,
              width,
              height,
              landmarks,
              rotation,
            );
          }

          // Trả về: [ID, Dữ liệu]
          mainSendPort.send([reqId, result]);
        } catch (e) {
          debugPrint("Worker Error: $e");
          mainSendPort.send([reqId, null]);
        }
      }
    });
  }

  // Helper: Trích xuất Landmark từ Face Object sang List<double>
  // Để tránh lỗi "Illegal argument in isolate message"
  List<double>? _extractLandmarks(Face face) {
    final lm = face.landmarks;
    final leftEye = lm[FaceLandmarkType.leftEye]?.position;
    final rightEye = lm[FaceLandmarkType.rightEye]?.position;

    if (leftEye == null || rightEye == null) return null;

    final list = List<double>.filled(10, 0.0);
    list[0] = leftEye.x.toDouble();
    list[1] = leftEye.y.toDouble();
    list[2] = rightEye.x.toDouble();
    list[3] = rightEye.y.toDouble();

    // Các điểm phụ
    final nose = lm[FaceLandmarkType.noseBase]?.position;
    if (nose != null) {
      list[4] = nose.x.toDouble();
      list[5] = nose.y.toDouble();
    }

    final lMouth = lm[FaceLandmarkType.leftMouth]?.position;
    if (lMouth != null) {
      list[6] = lMouth.x.toDouble();
      list[7] = lMouth.y.toDouble();
    }

    final rMouth = lm[FaceLandmarkType.rightMouth]?.position;
    if (rMouth != null) {
      list[8] = rMouth.x.toDouble();
      list[9] = rMouth.y.toDouble();
    }

    return list;
  }
}
