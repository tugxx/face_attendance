import 'dart:async';
import 'dart:isolate';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:get/get.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../types/face_pipeline.dart';
import '../services/log_service.dart';
import '../../data/models/registration_result.dart';

abstract class IsolateTask {
  final int reqId;
  IsolateTask({required this.reqId});
}

class DualTaskRequest extends IsolateTask {
  final int sessionHandle;
  final int address;
  final int width;
  final int height;
  final int yStride;
  final List<double> landmarks;
  final int rectX, rectY, rectW, rectH;
  final int rotation;
  final double recognitionThreshold;
  final double spoofThreshold;
  final double qualityThreshold;

  DualTaskRequest({
    required super.reqId,
    required this.sessionHandle,
    required this.address,
    required this.width,
    required this.height,
    required this.yStride,
    required this.landmarks,
    required this.rectX,
    required this.rectY,
    required this.rectW,
    required this.rectH,
    required this.rotation,
    required this.recognitionThreshold,
    required this.spoofThreshold,
    required this.qualityThreshold,
  });
}

class RegistrationTaskRequest extends IsolateTask {
  final int sessionHandle;
  final int address;
  final int width;
  final int height;
  final List<double> landmarks;
  final int rotation;
  final int recogPixelSize;

  RegistrationTaskRequest({
    required super.reqId,
    required this.sessionHandle,
    required this.address,
    required this.width,
    required this.height,
    required this.landmarks,
    required this.rotation,
    required this.recogPixelSize,
  });
}

class QualityCheckTaskRequest extends IsolateTask {
  final int sessionHandle;
  final int address;
  final int width;
  final int height;
  final int rectX, rectY, rectW, rectH;
  final int rotation;

  QualityCheckTaskRequest({
    required this.sessionHandle,
    required super.reqId,
    required this.address,
    required this.width,
    required this.height,
    required this.rectX,
    required this.rectY,
    required this.rectW,
    required this.rectH,
    required this.rotation,
  });
}

class EncodeJpegRequest extends IsolateTask {
  final int sessionHandle;
  final int address;
  final int width;
  final int height;
  final int rotation;

  EncodeJpegRequest({
    required super.reqId,
    required this.sessionHandle,
    required this.address,
    required this.width,
    required this.height,
    required this.rotation,
  });
}
class FaceIsolateService extends GetxService {
  Isolate? _isolate;
  late SendPort _sendPort;
  ReceivePort? _receivePort;
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
    _isolate = await Isolate.spawn(_isolateEntryPoint, _receivePort!.sendPort);

    // Lắng nghe port
    _receivePort!.listen((message) {
      if (message is SendPort) {
        _sendPort = message;
        _isReady = true;

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

  void dispose() {
    if (!_isReady) return;
    _isReady = false;

    // 1. Đóng cổng nhận tín hiệu (Tránh leak memory Port)
    _receivePort?.close();
    _receivePort = null;

    // 2. GIẢI CỨU UI: Hủy bỏ mọi request đang bị kẹt chờ Isolate
    if (_pendingRequests.isNotEmpty) {
      for (var completer in _pendingRequests.values) {
        if (!completer.isCompleted) {
          // Trả về null để UI tự hiểu là luồng đã bị hủy, không bị treo await
          completer.complete(null);
        }
      }
      _pendingRequests.clear();
    }

    // 3. Ra lệnh tàn sát: Giết Isolate ngay lập tức
    if (_isolate != null) {
      _isolate!.kill(priority: Isolate.immediate);
      _isolate = null;
    }
  }

  Future<Map<String, dynamic>?> processDualTaskInIsolate({
    required int sessionHandle,
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
    required double recognitionThreshold,
    required double spoofThreshold,
    required double qualityThreshold,
  }) async {
    if (!_isReady) return null;

    final completer = Completer<dynamic>();
    int reqId = _nextRequestId++;
    _pendingRequests[reqId] = completer; // Lưu completer chờ Map kết quả

    final landmarksData = _extractLandmarks(face);

    final request = DualTaskRequest(
      reqId: reqId,
      sessionHandle: sessionHandle,
      address: address,
      width: width,
      height: height,
      yStride: yStride,
      landmarks: landmarksData!,
      rectX: rectX,
      rectY: rectY,
      rectW: rectW,
      rectH: rectH,
      rotation: rotation,
      recognitionThreshold: recognitionThreshold,
      spoofThreshold: spoofThreshold,
      qualityThreshold: qualityThreshold,
    );

    _sendPort.send(request);

    final result = await completer.future;
    return result as Map<String, dynamic>?;
  }

  Future<RegistrationResult?> processRegistrationInIsolate({
    required int sessionHandle,
    required int address,
    required int width,
    required int height,
    required Face face,
    required int rotation,
    required int recogPixelSize,
  }) async {
    if (!_isReady) return null;

    final completer = Completer<dynamic>();
    int reqId = _nextRequestId++;
    _pendingRequests[reqId] = completer;

    final landmarksData = _extractLandmarks(face);

    final request = RegistrationTaskRequest(
      reqId: reqId,
      sessionHandle: sessionHandle,
      address: address,
      width: width,
      height: height,
      landmarks: landmarksData!,
      rotation: rotation,
      recogPixelSize: recogPixelSize,
    );

    _sendPort.send(request);

    final result = await completer.future;
    return result as RegistrationResult?;
  }

  // --- THÊM HÀM GỌI TỪ LUỒNG CHÍNH ---
  Future<double> processQualityInIsolate({
    required int sessionHandle,
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

    final request = QualityCheckTaskRequest(
      sessionHandle: sessionHandle,
      reqId: reqId,
      address: address,
      width: width,
      height: height,
      rectX: rect.left.toInt(),
      rectY: rect.top.toInt(),
      rectW: rect.width.toInt(),
      rectH: rect.height.toInt(),
      rotation: rotation,
    );

    _sendPort.send(request);

    final result = await completer.future;
    return (result as num?)?.toDouble() ?? -1.0;
  }

  Future<Uint8List?> encodeJpegInIsolate({
    required int sessionHandle,
    required int address,
    required int width,
    required int height,
    required int rotation,
  }) async {
    if (!_isReady) return null;

    final completer = Completer<dynamic>();
    int reqId = _nextRequestId++;
    _pendingRequests[reqId] = completer;

    final request = EncodeJpegRequest(
      reqId: reqId,
      sessionHandle: sessionHandle,
      address: address,
      width: width,
      height: height,
      rotation: rotation,
    );

    _sendPort.send(request);

    final result = await completer.future;
    return result as Uint8List?;
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
      if (message is! IsolateTask) return;

      try {
        if (message is DualTaskRequest) {
          final result = FaceImagePipelineNative.processDualTask(
            sessionHandle: message.sessionHandle,
            ptrYuv: Pointer<Uint8>.fromAddress(message.address),
            width: message.width,
            height: message.height,
            yStride: message.yStride,
            landmarks: message.landmarks,
            rotation: message.rotation,
            rectX: message.rectX,
            rectY: message.rectY,
            rectW: message.rectW,
            rectH: message.rectH,
            recognitionThreshold: message.recognitionThreshold,
            spoofThreshold: message.spoofThreshold,
            qualityThreshold: message.qualityThreshold,
          );
          // Trả về: [ID, Dữ liệu]
          mainSendPort.send([message.reqId, result]);
        } else if (message is RegistrationTaskRequest) {
          final RegistrationResult? result =
              FaceImagePipelineNative.processRegistration(
                sessionHandle: message.sessionHandle,
                ptrYuv: Pointer<Uint8>.fromAddress(message.address),
                width: message.width,
                height: message.height,
                landmarks: message.landmarks,
                rotation: message.rotation,
                recogPixelSize: message.recogPixelSize,
              );
          mainSendPort.send([message.reqId, result]);
        } else if (message is QualityCheckTaskRequest) {
          final double score = FaceImagePipelineNative.processQuality(
            sessionHandle: message.sessionHandle,
            ptrYuv: Pointer<Uint8>.fromAddress(message.address),
            width: message.width,
            height: message.height,
            rotation: message.rotation,
            rectX: message.rectX,
            rectY: message.rectY,
            rectW: message.rectW,
            rectH: message.rectH,
          );
          mainSendPort.send([message.reqId, score]);
        } else if (message is EncodeJpegRequest) {
          final result = FaceImagePipelineNative.encodeYuvToJpeg(
            sessionHandle: message.sessionHandle,
            ptrYuv: Pointer<Uint8>.fromAddress(message.address),
            width: message.width,
            height: message.height,
            rotation: message.rotation,
          );
          mainSendPort.send([message.reqId, result]);
        }
      } catch (e) {
        AppLog.error("Worker Error: $e");
        mainSendPort.send([message.reqId, null]);
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
