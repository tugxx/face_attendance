import 'dart:async';
import 'dart:isolate';
import 'dart:ffi';

// import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../../app/types/face_progress.dart';
import '../services/log_service.dart';
import '../../data/models/registration_result.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

class FaceIsolateService extends GetxService {
  // late Isolate _isolate;
  late SendPort _sendPort;
  ReceivePort? _receivePort;
  // final _responseStream = StreamController<dynamic>.broadcast();
  bool _isReady = false;

  // Dùng Map để lưu các Completer đang chờ, Key là ID
  final Map<int, Completer<dynamic>> _pendingRequests = {};
  int _nextRequestId = 0;

  // Khởi tạo Isolate
  Future<void> start() async {
    // final sw = Stopwatch()..start(); // ⏱️ Bắt đầu đo

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

        // sw.stop(); // ⏱️ Dừng đo
        // AppLog.info("⏱️ Thời gian Spawn Isolate: ${sw.elapsedMilliseconds}ms");
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

  // // --- HÀM 1: CROP NHẬN DIỆN (112x112) ---
  // Future<List<double>?> processInIsolate(
  //   Uint8List yuvBytes,
  //   int w,
  //   int h,
  //   Face face,
  //   int rot,
  // ) async {
  //   return _sendRequest(yuvBytes, w, h, face, rot, 0); // Type 0
  // }

  // // --- HÀM 2: CROP ANTI-SPOOF ---
  // Future<List<double>?> processAntiSpoofInIsolate(
  //   Uint8List yuvBytes,
  //   int w,
  //   int h,
  //   Face face,
  //   int rotation,
  //   int targetSize,
  // ) async {
  //   return _sendRequest(
  //     yuvBytes,
  //     w,
  //     h,
  //     face,
  //     rotation,
  //     1,
  //     targetSize,
  //   ); // Type 1
  // }

  Future<Map<String, List<double>?>?> processDualTaskInIsolate({
    required int address,
    required int width,
    required int height,
    required int yStride,
    // required int uvStride,
    required Face face,
    required int rectX,
    required int rectY,
    required int rectW,
    required int rectH,
    required int rotation,
    required int spoofSize,
  }) async {
    if (!_isReady) return null;

    final completer = Completer<Map<String, List<double>?>?>();
    int reqId = _nextRequestId++;
    _pendingRequests[reqId] = completer; // Lưu completer chờ Map kết quả

    final landmarksData = _extractLandmarks(face);

    // AppLog.info("Địa chỉ YUV gửi sang Isolate: $address");
    _sendPort.send([
      reqId,
      address,
      width,
      height,
      yStride,
      // uvStride,
      landmarksData,
      rectX,
      rectY,
      rectW,
      rectH,
      rotation,
      0, // type: 0 bây giờ hiểu là chạy Dual Task
      spoofSize,
    ]);

    return completer.future;
  }

  Future<RegistrationResult?> processRegistrationInIsolate({
    required int address,
    required int width,
    required int height,
    required Face face,
    required int rotation,
  }) async {
    if (!_isReady) return null;

    final completer = Completer<RegistrationResult?>();
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
    ]);

    return completer.future;
  }

  // Future<List<double>?> _sendRequest(
  //   Uint8List yuvBytes,
  //   int width,
  //   int height,
  //   Face face,
  //   int rotation,
  //   int type, [
  //   int targetSize = 112,
  // ]) async {
  //   if (!_isReady) return null;

  //   final completer = Completer<List<double>?>();
  //   int reqId = _nextRequestId++;
  //   _pendingRequests[reqId] = completer;

  //   final landmarksData = _extractLandmarks(face);
  //   if (landmarksData == null) {
  //     _pendingRequests.remove(reqId);
  //     return null;
  //   }

  //   final transferableYuv = TransferableTypedData.fromList([yuvBytes]);

  //   _sendPort.send([
  //     reqId,
  //     transferableYuv,
  //     width,
  //     height,
  //     landmarksData,
  //     rotation,
  //     type, // Thêm type vào cuối
  //     targetSize,
  //   ]);

  //   final result = await completer.future;
  //   return result;
  // }

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
    FaceProcessorNative.init();

    port.listen((message) {
      if (message is! List) return;

      int reqId = message[0]; // Nhận ID
      final int address = message[1];
      final int width = message[2];
      final int height = message[3];
      final int yStride = message[4];
      // final int uvStride = message[5];
      final List<double> landmarks = message[5]; // Nhận list landmarks
      final int rectX = message[6];
      final int rectY = message[7];
      final int rectW = message[8];
      final int rectH = message[9];
      final int rotation = message[10];
      // final int spoofModelType = message[12];
      final int taskType = message[11]; // 0 = Dual Task, 1 = Registration
      final int spoofTargetSize = message[12];

      try {
        final Pointer<Uint8> ptrYuv = Pointer<Uint8>.fromAddress(address);

        if (taskType == 0) {
          final result = FaceProcessorNative.processDualTask(
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
          );

          // Trả về: [ID, Dữ liệu]
          mainSendPort.send([reqId, result]);
        } else if (taskType == 1) {
          // ----------------------------------------------------
          // TYPE 1: ĐĂNG KÝ KHOÉT ẢNH VÀ TẠO JPG
          // ----------------------------------------------------
          final List<double>? aiPixels =
              FaceProcessorNative.processRegistration(
                ptrYuv: ptrYuv, // Đã có sẵn từ address
                width: width, // Đã nhận từ message
                height: height, // Đã nhận từ message
                landmarks: landmarks, // Đã nhận từ message
                rotation: rotation, // Đã nhận từ message
              );

          if (aiPixels == null) {
            mainSendPort.send([reqId, null]);
            return;
          }

          // Vẽ ảnh JPG trực tiếp bên trong Isolate này luôn (Không làm đơ UI)
          final image = img.Image(width: 112, height: 112);
          for (int y = 0; y < 112; y++) {
            for (int x = 0; x < 112; x++) {
              int index = (y * 112 + x) * 3;
              double r = (aiPixels[index] * 128.0) + 127.5;
              double g = (aiPixels[index + 1] * 128.0) + 127.5;
              double b = (aiPixels[index + 2] * 128.0) + 127.5;
              image.setPixelRgb(x, y, r.toInt(), g.toInt(), b.toInt());
            }
          }

          Uint8List displayBytes = Uint8List.fromList(
            img.encodeJpg(image, quality: 100),
          );

          // Trả về thẳng object RegistrationResult
          mainSendPort.send([
            reqId,
            RegistrationResult(aiPixels, displayBytes),
          ]);
        }
      } catch (e) {
        // AppLog.error("Worker Error: $e");
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

  // void stop() {
  //   _isReady = false;

  //   // 1. Kết thúc tất cả các yêu cầu đang đợi với một lỗi
  //   _pendingRequests.forEach((id, completer) {
  //     if (!completer.isCompleted) {
  //       completer.completeError("Isolate stopped");
  //     }
  //   });
  //   _pendingRequests.clear();

  //   // 2. Kill isolate
  //   _isolate.kill(priority: Isolate.immediate);
  // }
}
