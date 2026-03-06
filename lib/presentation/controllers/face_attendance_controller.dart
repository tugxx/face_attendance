import 'dart:io';
import 'dart:ffi';
import 'dart:math' as math;
import 'dart:async';

import 'package:ffi/ffi.dart';
import 'package:camera/camera.dart';
// import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:permission_handler/permission_handler.dart';
// import 'package:path_provider/path_provider.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

import '../../app/utils/camera_utils.dart';
import '../../app/services/face_recognition_service.dart';
import '../../app/services/face_isolate_service.dart';
import '../../app/services/face_antispoofing_service.dart';
import '../../app/services/face_smoothier_service.dart';
import '../../app/services/log_service.dart';

class FaceCheckinState {
  // Biến cấu hình
  static const int requiredRecognitionStreak =
      3; // Cần 3 lần nhận diện đúng tên
  // static const int requiredLivenessStreak = 3; // Cần 3 lần check liveness OK
  static const int requiredSpoofStreak = 5; // Cần 5 lần phát hiện giả mạo

  // Biến trạng thái runtime
  String? currentCandidate; // Tên người đang theo dõi
  int matchStreak = 0; // Đếm số lần nhận diện đúng liên tiếp
  int spoofStreak = 0; // Đếm số lần phát hiện giả mạo liên tiếp
  int livenessStreak = 0; // Đếm số lần liveness pass liên tiếp
  bool isSuccessCooldown = false; // Chế độ chờ sau khi điểm danh thành công

  void reset() {
    currentCandidate = null;
    matchStreak = 0;
    livenessStreak = 0;
  }
}

// Khởi tạo instance (Để trong Controller của bạn)
final checkinState = FaceCheckinState();

class FaceAttendanceController extends GetxController {
  CameraController? cameraController;
  // final FaceRecognitionService _aiService = FaceRecognitionService();
  // final _spoofService = FaceAntiSpoofingService();

  final FaceRecognitionService _aiService = Get.find<FaceRecognitionService>();
  final FaceAntiSpoofingService _spoofService =
      Get.find<FaceAntiSpoofingService>();

  final FaceIsolateService _isolateService = Get.find<FaceIsolateService>();

  final _smoother = BBoxSmoother();

  final AudioPlayer _audioPlayer = AudioPlayer();

  var isInitialized = false.obs; // Cờ báo hiệu Camera đã bật chưa.
  var recognizedName = "Unknown".obs;
  // Cái "khóa" (Lock/Semaphore) để ngăn không cho xử lý quá nhiều frame cùng lúc (tránh tràn RAM).
  var isProcessing = false.obs;
  var isAiReady = false.obs;
  var errorMsg = "".obs;
  final RxBool isSpoofing = false.obs;

  DateTime _lastRecognitionTime = DateTime.fromMillisecondsSinceEpoch(0);
  late FaceDetector _faceDetector;
  var detectedFaces = <Face>[].obs;

  CameraDescription? _currentCamera;

  var faceInstruction = "".obs;

  Pointer<Uint8>? nativeBuffer;
  int _currentBufferSize = 0;

  // ------------------------------------------------------
  // HELPER
  // ------------------------------------------------------

  bool _shouldSkipRecognition() {
    // Nếu chưa đủ 500ms kể từ lần nhận diện trước -> Skip
    final now = DateTime.now();
    if (now.difference(_lastRecognitionTime).inMilliseconds < 500) {
      return true;
    }

    _lastRecognitionTime = now;

    return false;
  }

  Future<Face?> _detectFaceFromImage(CameraImage image) async {
    // 1. Chuyển đổi dữ liệu
    // Gọi hàm static từ Utils
    final inputImage = CameraUtils.convertCameraImageToInputImage(
      image,
      _currentCamera!,
    );
    // Nếu convert lỗi (do format lạ hoặc xoay không đúng) -> Bỏ qua frame này
    if (inputImage == null) return null;

    // 2. Gửi cho ML Kit xử lý
    final faces = await _faceDetector.processImage(inputImage);

    detectedFaces.assignAll(faces);

    if (faces.isEmpty) return null;

    final face = faces.first;
    // Lọc khuôn mặt quá nhỏ
    if (face.boundingBox.width < 80 || face.boundingBox.height < 80) {
      return null;
    }

    // Lọc khuôn mặt quá to (Gần camera)
    // Lấy kích thước khung hình từ metadata của ML Kit (đã xử lý xoay chuẩn xác)
    final imageSize = inputImage.metadata?.size;
    if (imageSize != null) {
      final actualWidth = math.min(imageSize.width, imageSize.height);

      final widthRatio = face.boundingBox.width / actualWidth;

      // Ngưỡng : Mặt chiếm > % chiều ngang màn hình -> Quá gần
      if (widthRatio > 0.85) {
        // AppLog.warning(
        //   "Khuôn mặt quá gần camera! Tỷ lệ ngang: ${(widthRatio * 100).toInt()}%",
        // );
        faceInstruction.value = "⚠️ Quá gần! Vui lòng lùi ra xa";
        return null;
      }

      faceInstruction.value = "";
    }

    return face;
  }

  // Future<String?> _generateDebugPath() async {
  //   try {
  //     final dir = await getExternalStorageDirectory();
  //     if (dir != null) {
  //       // 1. Đặt tên file cố định
  //       final String path = '${dir.path}/debug_face.jpg';

  //       // 2. In đường dẫn ra console để debug
  //       AppLog.info("💾 File path: $path");

  //       return path;
  //     }
  //   } catch (e) {
  //     AppLog.warning("⚠️ Lỗi tạo đường dẫn: $e");
  //   }
  //   return null;
  // }

  Future<void> _performRecognition(
    List<double> recogPixels, // 112x112
    List<double> spoofPixels, // 80x80
    /*Stopwatch sw,*/
  ) async {
    if (checkinState.isSuccessCooldown) {
      return;
    }

    if (recogPixels.isEmpty) {
      AppLog.warning("⚠️ Lỗi: Dữ liệu khuôn mặt rỗng!");
      return;
    }

    // int tStartAI = sw.elapsedMilliseconds;

    try {
      // ---------------------------------------------------------
      // CHẠY SONG SONG (Parallel Execution)
      // ---------------------------------------------------------

      // Gọi nhận diện danh tính
      final futureIdentity = _aiService.predict(recogPixels);

      // Gọi Liveness (Anti-Spoofing) luôn, không cần chờ ID
      final futureLiveness = _spoofService.predict(spoofPixels);

      // Chờ cả 2 kết quả trả về
      final results = await Future.wait([futureIdentity, futureLiveness]);

      // futureIdentity.then((recognition) {
      //   AppLog.info("Độ similarity: ${recognition.distance}");
      // });

      // int tEndAI = sw.elapsedMilliseconds;
      // AppLog.info("3️⃣ AI Inference (2 Models): ${tEndAI - tStartAI} ms");

      final RecognitionResult idResult = results[0] as RecognitionResult;
      final bool isRealPerson = results[1] as bool;

      String detectedName = idResult.isUnknown ? "Unknown" : idResult.name;

      // ---------------------------------------------------------
      // GỘP LOGIC (Combined Logic)
      // Điều kiện: Phải ĐÚNG NGƯỜI và PHẢI LÀ NGƯỜI THẬT cùng lúc
      // ---------------------------------------------------------

      if (detectedName != "Unknown" && isRealPerson) {
        // ✅ QUAN TRỌNG: Xóa lỗi cũ ngay khi nhận diện thành công
        if (errorMsg.value.isNotEmpty) {
          errorMsg.value = "";
        }

        checkinState.spoofStreak = 0;
        isSpoofing.value = false;

        // Nếu là người mới hoặc đang track dở người này
        if (detectedName == checkinState.currentCandidate) {
          checkinState.matchStreak++; // Tăng điểm tin cậy
        } else {
          // Đổi người -> Reset
          checkinState.currentCandidate = detectedName;
          checkinState.matchStreak = 1;
          // AppLog.info("🔄 Tracking new: $detectedName");
        }

        // AppLog.info(
        //   "🚀 Verified: $detectedName | Progress: ${checkinState.matchStreak}/3",
        // );

        // Đủ điều kiện check-in (Ví dụ: 3 lần liên tiếp đúng cả ID lẫn Liveness)
        if (checkinState.matchStreak >=
            FaceCheckinState.requiredRecognitionStreak) {
          recognizedName.value = checkinState.currentCandidate!;

          // await _handleCheckinSuccess(checkinState.currentCandidate!);
          unawaited(_handleCheckinSuccess(checkinState.currentCandidate!));

          checkinState.isSuccessCooldown =
              true; // Bật cooldown ngay khi check-in thành công
        }
      } else {
        // Reset streak nếu đứt quãng
        checkinState.matchStreak = 0;

        // A. NẾU LÀ GIẢ MẠO (Spoof)
        if (!isRealPerson) {
          isSpoofing.value = true;

          checkinState.spoofStreak++;
          // AppLog.warning(
          //   "⚠️ SPOOF DETECTED for $detectedName | Streak: ${checkinState.spoofStreak}",
          // );

          if (checkinState.spoofStreak >=
              FaceCheckinState.requiredSpoofStreak) {
            errorMsg.value = "⚠️ Cảnh báo: Phát hiện khuôn mặt không hợp lệ!";

            // TODO: Gửi cảnh báo gian lận về server tại đây
            // unawaited(_reportSpoofToServer(detectedName));

            // Tuỳ chọn: Bật cooldown để khoá nhận diện trong 2-3 giây
            checkinState.isSuccessCooldown = true;
            Future.delayed(const Duration(seconds: 3), () {
              checkinState.isSuccessCooldown = false;
              errorMsg.value = ""; // Xóa chữ thông báo
              isSpoofing.value = false; // Xóa luôn viền đỏ
            });

            // Có thể reset spoofStreak sau khi đã cảnh báo, hoặc để nó giữ nguyên
            // cho đến khi frame nhận ra người thật (đã xử lý ở block trên)
            checkinState.spoofStreak = 0; // Reset sau khi đã cảnh báo
          }
          return; // Dừng xử lý frame này
        } else {
          // B. NẾU LÀ NGƯỜI THẬT NHƯNG KHÔNG NHẬN RA (Unknown)
          // Hoặc frame này bình thường trở lại -> Xóa lỗi "Giả mạo" đi
          isSpoofing.value = false;
          // checkinState.spoofStreak = 0;
          errorMsg.value = ""; // ✅ Reset về trạng thái bình thường
        }

        // Không reset currentCandidate ngay để tránh UI nhấp nháy, chỉ reset điểm
      }
    } catch (e, stack) {
      AppLog.error("❌ Error: $e");
      AppLog.error('Stack trace: $stack');
    } finally {}
  }

  Future<void> _handleCheckinSuccess(String name) async {
    checkinState.isSuccessCooldown = true; // Khóa hệ thống

    await _audioPlayer.setVolume(1.0);
    await _audioPlayer.play(
      AssetSource(
        'sounds/miraclei-sample_confirm_accept01_kofi_by_miraclei-364181.mp3',
      ),
    );

    HapticFeedback.vibrate();

    // AppLog.info("🎉 CHECKIN SUCCESS: $name");

    recognizedName.value = name;

    // TODO: Gửi API log lên server tại đây...

    // Wait 3 giây rồi reset (Logic Python: success_mode active duration)
    await Future.delayed(const Duration(seconds: 3));

    recognizedName.value = "Unknown";
    checkinState.reset();
    checkinState.isSuccessCooldown = false; // Mở khóa lại
  }

  // ------------------------------------------------------
  // INIT FUNCTION
  // ------------------------------------------------------

  @override
  void onInit() async {
    super.onInit();

    // await _spoofService.initialize();

    try {
      // Bắt đầu quy trình khởi tạo
      isInitialized.value = false;
      isAiReady.value = false;

      // // Khởi động Worker (Chỉ 1 lần duy nhất)
      // await _isolateService.start();

      // // Khởi tạo Service Nhận diện khuôn mặt (Custom AI)
      // // Đây là bước nạp Model (ví dụ: mobilefacenet.tflite) và dữ liệu nhân viên vào RAM.
      // // Từ khóa 'await': Đợi nạp xong xuôi mới chạy dòng tiếp theo (tránh lỗi chưa load model mà đã dùng).
      // await _aiService.initialize();

      // 2. Cấu hình ML Kit
      _faceDetector = FaceDetector(
        options: FaceDetectorOptions(
          performanceMode: FaceDetectorMode.fast, // Ưu tiên độ chính xác
          enableContours:
              false, // Không cần vẽ đường viền bao quanh mặt (giúp giảm tải xử lý nếu không dùng để vẽ UI).
          // Bật tìm các điểm mốc (Mắt, mũi, miệng, má...).
          // QUAN TRỌNG: Dùng để căn chỉnh (align) khuôn mặt cho thẳng trước khi đưa vào AI nhận diện.
          enableLandmarks: true,
          enableClassification: false,
          minFaceSize: 0.15,
        ),
      );

      await startCamera();

      // Mọi thứ đã xong, giờ mới cho phép hiện UI Camera
      isInitialized.value = true;
      isAiReady.value = true;
    } catch (e) {
      errorMsg.value = "Lỗi khởi tạo: $e";
    }
  }

  Future<void> startCamera() async {
    // Reset lỗi cũ trước khi bắt đầu
    errorMsg.value = "";

    try {
      // 1. KIỂM TRA QUYỀN TRUY CẬP
      var status = await Permission.camera.request();
      if (!status.isGranted) {
        errorMsg.value = "Vui lòng cấp quyền Camera";
        return;
      }

      // 2. TÌM KIẾM CAMERA KHẢ DỤNG
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        errorMsg.value = "Không tìm thấy Camera";
        return;
      }

      // 3. CHỌN CAMERA TRƯỚC (Ưu tiên Selfie)
      // Logic: Cố tìm cam trước, nếu không có thì lấy cam đầu tiên (cam sau)
      _currentCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      // 4. CẤU HÌNH CONTROLLER
      cameraController = CameraController(
        _currentCamera!,
        ResolutionPreset.medium,
        enableAudio: false, // Tắt thu âm cho nhẹ, vì chấm công không cần tiếng
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup
                  .nv21 // Android
            : ImageFormatGroup.bgra8888, // iOS
      );

      // 5. KHỞI ĐỘNG PHẦN CỨNG
      await cameraController!.initialize();

      // Khối 1: Xử lý Lấy nét (Focus)
      try {
        // Chuyển sang AUTO thay vì LOCKED.
        // Điện thoại hay bị thay đổi khoảng cách cầm tay. Chuyển sang Auto để mặt lúc nào cũng nét.
        await cameraController!.setFocusMode(FocusMode.auto);
      } catch (e) {
        AppLog.warning("⚠️ Camera: Lỗi set FocusMode: $e");
      }

      // Khối 3: Cứ để Auto Exposure (XÓA ĐOẠN KHÓA SÁNG CŨ ĐI)
      try {
        // Đảm bảo camera luôn tự thích nghi với môi trường
        await cameraController!.setExposureMode(ExposureMode.auto);
      } catch (e) {
        AppLog.warning("⚠️ Camera: Lỗi set ExposureMode: $e");
      }

      // 6. BẮT ĐẦU STREAM HÌNH ẢNH
      // Truyền hàm _processFrame vào để xử lý từng khung hình
      await cameraController!.startImageStream(processFrame);

      // 7. HOÀN TẤT
      // Chỉ khi stream chạy thành công mới báo UI hiển thị
      isInitialized.value = true;
    } catch (e) {
      // Bắt lỗi phần cứng (VD: Camera bị hỏng, bị chiếm dụng...)
      errorMsg.value = "Lỗi khởi động Camera: $e";
      isInitialized.value = false; // Đảm bảo UI không hiện khung camera đen
    }
  }

  void processFrame(CameraImage image) async {
    if (checkinState.isSuccessCooldown || recognizedName.value != "Unknown") {
      return;
    }

    if (isProcessing.value) return;

    // Khoá luồng xử lý nhận diện
    isProcessing.value = true;

    // // ⏱️ BẮT ĐẦU ĐỒNG HỒ
    // final Stopwatch sw = Stopwatch()..start();

    Face? face;

    try {
      // 1. Detect khuôn mặt (ML Kit - Giữ nguyên)
      face = await _detectFaceFromImage(image);

      // int tDetect = sw.elapsedMilliseconds;

      // Nếu không có mặt -> Dừng
      if (face == null) {
        _smoother.reset();
        if (checkinState.matchStreak > 0) {
          checkinState.matchStreak = 0;
          AppLog.warning("❌ Face lost. Reset streak.");
        }
        return;
      }

      // // Log Detect (Nên < 80ms)
      // AppLog.info("1️⃣ Detect: ${tDetect}ms");

      // 2. Throttling (Giữ nguyên)
      if (_shouldSkipRecognition()) {
        return;
      }

      // // 4. Chuẩn bị dữ liệu gửi sang Isolate
      final int totalBytes = image.planes.fold(
        0,
        (sum, plane) => sum + plane.bytes.length,
      );
      // nativeBuffer = calloc<Uint8>(totalBytes);
      if (nativeBuffer == null || _currentBufferSize != totalBytes) {
        if (nativeBuffer != null) {
          calloc.free(nativeBuffer!);
        }
        nativeBuffer = calloc<Uint8>(totalBytes);
        _currentBufferSize = totalBytes;
      }

      // Copy nhanh từ mảng bytes của camera vào native buffer
      int offset = 0;
      for (var plane in image.planes) {
        nativeBuffer!.asTypedList(totalBytes).setAll(offset, plane.bytes);
        offset += plane.bytes.length;
      }

      // final int uvStride = image.planes.length > 1
      //     ? image.planes[1].bytesPerRow
      //     : image.planes[0].bytesPerRow;

      final faceRect = _smoother.smooth(face.boundingBox);

      // // 5. Gửi sang Isolate -> Gọi C++ Native
      // // Đo thời gian bắt đầu gửi
      // int tStartCrop = sw.elapsedMilliseconds;

      // 5. Gửi sang Isolate (Xử lý ảnh bằng Dart thuần)
      // Input: YUV -> Output: List<double> (Pixels đã chuẩn hóa)
      // AppLog.info("🚀 Gửi task sang Isolate...");

      final dualResult = await _isolateService.processDualTaskInIsolate(
        address: nativeBuffer!.address,
        width: image.width,
        height: image.height,
        yStride: image.planes[0].bytesPerRow,
        // uvStride: uvStride,
        face: face,
        rectX: faceRect.left.toInt(),
        rectY: faceRect.top.toInt(),
        rectW: faceRect.width.toInt(),
        rectH: faceRect.height.toInt(),
        rotation: cameraController?.description.sensorOrientation ?? 0,
        spoofSize: _spoofService.inputWidth,
      );

      // int tEndCrop = sw.elapsedMilliseconds;
      // int tCrop = tEndCrop - tStartCrop; // Thời gian thực tế của bước Crop
      // AppLog.info("2️⃣ Crop & Align (Isolate): $tCrop ms");

      if (dualResult == null) {
        AppLog.warning("⚠️ Isolate trả về null, bỏ qua frame này");
        return; // Lệnh finally ở cuối processFrame sẽ tự động gán isProcessing = false
      }

      final List<double>? recogCrop = dualResult['recog'];
      final List<double>? spoofCrop = dualResult['spoof'];

      // 6. Có kết quả từ Isolate -> Đưa vào Model
      if (recogCrop != null && spoofCrop != null) {
        // // --------------------------------------------------------------------------
        // try {
        //   // Lấy thư mục tạm
        //   final directory = await getExternalStorageDirectory();
        //   final file = File('${directory!.path}/dart_input_tensor.txt');

        //   // Ghi chuỗi các số thực, cách nhau bởi dấu phẩy
        //   String dataString = spoofCrop.join(',');
        //   await file.writeAsString(dataString);

        //   AppLog.info("✅ Đã lưu tensor dump tại: ${file.path}");
        //   AppLog.info(
        //     "👉 Hãy copy file này sang máy tính để chạy script Python.",
        //   );
        // } catch (e) {
        //   AppLog.warning("⚠️ Lỗi tạo đường dẫn: $e");
        // }
        // // --------------------------------------------------------------------------

        await _performRecognition(recogCrop, spoofCrop /*, sw*/);

        // int tTotal = sw.elapsedMilliseconds;
        // AppLog.info(
        //   "⏱️ [${tTotal}ms] "
        //   "Detect: ${tDetect}ms | "
        //   "Crop: ${tCrop}ms | "
        //   "AI: ${tTotal - tEndCrop}ms | "
        //   "FPS: ${(1000 / tTotal).toStringAsFixed(1)}",
        // );
      } else {
        AppLog.warning("⚠️ Isolate trả về null (Do mặt nghiêng hoặc lỗi ảnh)");
      }
    } catch (e, s) {
      AppLog.error("❌ Lỗi processFrame: $e");
      AppLog.error("Dấu vết (StackTrace):\n$s");
      // isProcessing.value = false;
    } finally {
      // if (nativeBuffer != null) {
      //   calloc.free(nativeBuffer);
      // }

      // _safeguardUnlock(); // Đảm bảo an toàn
      isProcessing.value = false; // Mở khóa để xử lý frame tiếp theo

      // // Tổng kết thời gian 1 frame
      // sw.stop();
    }
  }

  @override
  void onClose() {
    // AppLog.info("🧹 Bắt đầu dọn dẹp tài nguyên màn hình Camera...");
    isProcessing.value = true;

    _audioPlayer.dispose();

    _faceDetector.close();
    // _isolateService.dispose();

    // Dọn dẹp RAM
    if (nativeBuffer != null) {
      calloc.free(nativeBuffer!);
      nativeBuffer = null;
    }

    // Xử lý Camera an toàn
    if (cameraController != null) {
      if (cameraController!.value.isStreamingImages) {
        cameraController!
            .stopImageStream()
            .then((_) {
              cameraController!.dispose();
              // AppLog.info("✅ Đã giải phóng Camera an toàn");
            })
            .catchError((e) {
              AppLog.error(
                "❌ Lỗi khi đóng camera: $e",
              ); // Bắt lỗi lỡ phần cứng kẹt
            });
      } else {
        cameraController!.dispose();
        AppLog.info("✅ Đã giải phóng Camera");
      }
    }

    super.onClose();
  }
}
