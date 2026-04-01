import 'dart:async';
import 'dart:isolate';
import 'dart:ffi';

// import 'package:flutter/foundation.dart';
// import 'package:ffi/ffi.dart'; //
import 'package:get/get.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../types/face_pipeline.dart';
import '../services/log_service.dart';
import '../../data/models/registration_result.dart';

// import 'package:flutter/foundation.dart';
// import 'package:flutter/services.dart';
// import 'package:image/image.dart' as img;

class FaceIsolateService extends GetxService {
  // late Isolate _isolate;
  late SendPort _sendPort;
  ReceivePort? _receivePort;
  // final _responseStream = StreamController<dynamic>.broadcast();
  bool _isReady = false;

  final Map<int, Completer<dynamic>> _pendingRequests = {};
  int _nextRequestId = 0;

  // Khởi tạo Isolate
  Future<void> start() async {
    if (_isReady) return;

    // 1. Tạo một cái Barie
    final completer = Completer<void>();

    _receivePort = ReceivePort();

    // Spawn Isolate
    Isolate.spawn(_isolateEntryPoint, _receivePort!.sendPort);

    // Lắng nghe port
    _receivePort!.listen((message) {
      if (message is SendPort) {
        _sendPort = message;
        _isReady = true;

        AppLog.info("✅ FaceIsolateService: Worker Started!");

        // 2. MỞ BARIE: Lúc này hàm start() mới thực sự được xem là hoàn thành
        if (!completer.isCompleted) {
          completer.complete();
        }
      } else if (message is List) {
        // Message trả về: [RequestId, ResultList]
        int reqId = message[0];
        dynamic result = message[1];

        // Tìm và complete đúng request
        if (_pendingRequests.containsKey(reqId)) {
          _pendingRequests[reqId]?.complete(result);
          _pendingRequests.remove(reqId);
        }
      }
    });

    // 3. Bắt luồng chính đứng chờ ở Barie
    return completer.future;
  }

  Future<Map<String, dynamic>?> processDualTaskInIsolate({
    required int address,
    required int width,
    required int height,
    required int yStride,
    required Face face,
    required int rectX,
    required int rectY,
    required int rectW,
    required int rectH,
    required int rotation,
    required int spoofSize,
    required double threshold,
  }) async {
    if (!_isReady) return null;

    final completer = Completer<dynamic>();
    int reqId = _nextRequestId++;
    _pendingRequests[reqId] = completer; // Lưu completer chờ Map kết quả

    final landmarksData = _extractLandmarks(face);

    // AppLog.info("Địa chỉ YUV gửi sang Isolate: $address");
    _sendPort.send([
      reqId, // 0
      address, // 1
      width, // 2
      height, // 3
      yStride, // 4
      landmarksData, // 5
      rectX, // 6
      rectY, // 7
      rectW, // 8
      rectH, // 9
      rotation, // 10
      0, // 11: type = 0: Dual Task
      spoofSize, // 12
      threshold, // 13
    ]);

    final result = await completer.future;
    return result as Map<String, dynamic>?;
  }

  Future<RegistrationResult?> processRegistrationInIsolate({
    required int address,
    required int width,
    required int height,
    required Face face,
    required int rotation,
  }) async {
    if (!_isReady) return null;

    final completer = Completer<dynamic>();
    int reqId = _nextRequestId++;
    _pendingRequests[reqId] = completer;

    final landmarksData = _extractLandmarks(face);

    _sendPort.send([
      reqId,
      address,
      width,
      height,
      0, // yStride (Không cần cho mode này, cứ truyền 0)
      landmarksData,
      0, 0, 0, 0, // rect (Không dùng)
      rotation,
      1, // 👈 type = 1: Báo cho Isolate biết đây là tác vụ ĐĂNG KÝ
      0, // spoofSize
      0.0, // threshold (không dùng, truyền 0.0) để mảng đủ độ dài
    ]);

    final result = await completer.future;
    return result as RegistrationResult?;
  }

  // --- THÊM HÀM GỌI TỪ LUỒNG CHÍNH ---
  Future<double> processQualityInIsolate({
    required int address,
    required int width,
    required int height,
    required Face face,
    required int rotation,
  }) async {
    if (!_isReady) return -1.0;

    final completer = Completer<dynamic>();
    int reqId = _nextRequestId++;
    _pendingRequests[reqId] = completer;

    // Lấy bounding box
    final rect = face.boundingBox;

    _sendPort.send([
      reqId,
      address, width, height, 0,
      <double>[], // landmarks (không cần)
      rect.left.toInt(),
      rect.top.toInt(),
      rect.width.toInt(),
      rect.height.toInt(),
      rotation,
      2, // 👈 type = 2: TÁC VỤ QUALITY CHECK
      0, 0.0,
    ]);

    final result = await completer.future;
    return (result as num?)?.toDouble() ?? -1.0;
  }

  // Hủy Isolate khi thoát app
  void reset() {
    // _isReady = false;

    // A. Giải phóng các luồng đang chờ (Chống treo app)
    _pendingRequests.forEach((id, completer) {
      if (!completer.isCompleted) {
        completer.completeError("Camera closed");
      }
    });
    _pendingRequests.clear();

    // // B. Đóng các cổng giao tiếp (Chống rò rỉ bộ nhớ)
    // _receivePort?.close();
    // _responseStream.close();

    // // C. Tiêu diệt Isolate ngay lập tức
    // _isolate.kill(priority: Isolate.immediate);

    AppLog.info("✅ Isolate Worker đã được đưa về trạng thái chờ (Idle)!");
  }

  // ----------------------------------------------------------------
  // LOGIC TRONG ISOLATE CON (WORKER)
  // ----------------------------------------------------------------
  static void _isolateEntryPoint(SendPort mainSendPort) {
    final port = ReceivePort();
    mainSendPort.send(port.sendPort); // Gửi cổng của mình cho Main

    // Load thư viện C++ 1 LẦN DUY NHẤT TẠI ĐÂY
    FaceImagePipelineNative.init();

    port.listen((message) {
      if (message is! List) return;

      int reqId = message[0]; // Nhận ID

      try {
        final int address = message[1];
        final int width = message[2];
        final int height = message[3];
        final int yStride = message[4];
        final List<double> landmarks = message[5]; // Nhận list landmarks
        final int rectX = message[6];
        final int rectY = message[7];
        final int rectW = message[8];
        final int rectH = message[9];
        final int rotation = message[10];
        final int taskType = message[11]; // 0 = Dual Task, 1 = Registration

        final Pointer<Uint8> ptrYuv = Pointer<Uint8>.fromAddress(address);

        if (taskType == 0) {
          final int spoofTargetSize = message[12];
          final double threshold = message[13];

          final result = FaceImagePipelineNative.processDualTask(
            ptrYuv: ptrYuv,
            width: width,
            height: height,
            yStride: yStride,
            landmarks: landmarks,
            rotation: rotation,
            rectX: rectX,
            rectY: rectY,
            rectW: rectW,
            rectH: rectH,
            spoofWidth: spoofTargetSize,
            spoofHeight: spoofTargetSize,
            threshold: threshold,
          );

          // Trả về: [ID, Dữ liệu]
          mainSendPort.send([reqId, result]);
        } else if (taskType == 1) {
          // ----------------------------------------------------
          // TYPE 1: ĐĂNG KÝ KHOÉT ẢNH VÀ TẠO JPG
          // ----------------------------------------------------
          final RegistrationResult? result =
              FaceImagePipelineNative.processRegistration(
                ptrYuv: ptrYuv, // Đã có sẵn từ address
                width: width, // Đã nhận từ message
                height: height, // Đã nhận từ message
                landmarks: landmarks, // Đã nhận từ message
                rotation: rotation, // Đã nhận từ message
              );

          if (result == null) {
            mainSendPort.send([reqId, null]);
            return;
          }

          mainSendPort.send([reqId, result]);
        } else if (taskType == 2) {
          // ----------------------------------------------------
          // TYPE 2: CHECK QUALITY (LIGHTQNET)
          // ----------------------------------------------------
          final double score = FaceImagePipelineNative.processQuality(
            ptrYuv: ptrYuv,
            width: message[2],
            height: message[3],
            rotation: message[10],
            rectX: message[6],
            rectY: message[7],
            rectW: message[8],
            rectH: message[9],
          );
          mainSendPort.send([reqId, score]);
        }
      } catch (e) {
        AppLog.error("Worker Error: $e");
        mainSendPort.send([reqId, null]);
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
