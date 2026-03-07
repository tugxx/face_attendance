import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import '../controllers/face_attendance_controller.dart';
import '../widgets/face_detector_painter.dart';

class FaceAttendanceView extends GetView<FaceAttendanceController> {
  const FaceAttendanceView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,

      body: Obx(() {
        // 1. Màn hình Loading (Khi chưa init xong HOẶC camera chưa có)
        if (!controller.isInitialized.value ||
            controller.cameraController == null) {
          return Container(
            color: Colors.black, // Nền đen cho đồng bộ
            width: double.infinity,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                CircularProgressIndicator(color: Colors.blue), // Vòng xoay
                SizedBox(height: 20),
                Text(
                  "Đang tải dữ liệu & Camera...",
                  style: TextStyle(color: Colors.white70, fontSize: 16),
                ),
              ],
            ),
          );
        }

        return Stack(
          fit: StackFit.expand,
          children: [
            // Layer 1: Camera Preview (Flutter tự xử lý scale/rotate để hiển thị full màn hình)
            CameraPreview(controller.cameraController!),

            // Layer 2: Vẽ khung
            Obx(() {
              // Nếu không có mặt thì không vẽ gì cả
              if (controller.detectedFaces.isEmpty ||
                  controller.recognizedName.value != "Unknown" ||
                  controller.errorMsg.value.isNotEmpty) {
                return const SizedBox.shrink();
              }

              // Quyết định màu viền
              Color boundingBoxColor = Colors.greenAccent;
              if (controller.errorMsg.value.isNotEmpty ||
                  controller.isSpoofing.value) {
                boundingBoxColor = Colors.redAccent; // Giả mạo -> Đỏ
              } else if (controller.faceInstruction.value.isNotEmpty) {
                boundingBoxColor = Colors.orangeAccent; // Nhắc nhở -> Cam
              }

              return SizedBox.expand(
                child: CustomPaint(
                  painter: FaceDetectorPainter(
                    controller.detectedFaces.toList(),
                    Size(
                      controller.cameraController!.value.previewSize!.width,
                      controller.cameraController!.value.previewSize!.height,
                    ),
                    InputImageRotationValue.fromRawValue(
                          controller
                              .cameraController!
                              .description
                              .sensorOrientation,
                        ) ??
                        InputImageRotation.rotation0deg,
                    controller.cameraController!.description.lensDirection,
                    boundingBoxColor,
                  ),
                ),
              );
            }),

            // Layer UI điều khiển (Nút back, trạng thái text...)
            _buildOverlayUI(),

            // ✅ LAYER 4: MÀN HÌNH THÀNH CÔNG (SUCCESS OVERLAY)
            Obx(() {
              // Nếu chưa nhận ra ai thì tàng hình
              if (controller.recognizedName.value == "Unknown") {
                return const SizedBox.shrink();
              }

              // Nếu nhận diện thành công -> Phủ màn hình đen mờ và hiện chữ
              return Container(
                color: Colors.black.withValues(
                  alpha: 0.7,
                ), // Làm mờ camera đi 70%
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Icon check mark xanh lá to đùng
                      const Icon(
                        Icons.check_circle,
                        color: Colors.greenAccent,
                        size: 100,
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        "Điểm danh thành công",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 10),
                      // Tên người dùng
                      Text(
                        "Xin chào, ${controller.recognizedName.value}!",
                        style: const TextStyle(
                          color: Colors.greenAccent,
                          fontSize: 22,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),

            // ✅ LAYER 5: NÚT BACK (Thoát về màn hình Home)
            Positioned(
              top: 20, // Khoảng cách từ trên xuống
              left: 16, // Khoảng cách từ mép trái
              child: SafeArea(
                // SafeArea giúp nút không bị lẹm vào "tai thỏ" hoặc thanh trạng thái
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(
                      alpha: 0.4,
                    ), // Phủ nền mờ để nút luôn hiện rõ trên mọi nền camera
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: const Icon(
                      Icons.arrow_back_ios_new, // Icon mũi tên quay lại
                      color: Colors.white,
                      size: 24,
                    ),
                    onPressed: () {
                      Get.back(); // Lệnh GetX siêu ngắn gọn để đóng màn hình hiện tại
                    },
                  ),
                ),
              ),
            ),
          ],
        );
      }),
    );
  }

  Widget _buildOverlayUI() {
    return Positioned(
      bottom: 80,
      left: 20,
      right: 20,
      child: Center(
        child: Obx(() {
          if (controller.recognizedName.value != "Unknown") {
            return const SizedBox.shrink(); // Trả về widget tàng hình
          }

          if (controller.isSpoofing.value &&
              controller.errorMsg.value.isEmpty) {
            return const SizedBox.shrink();
          }

          // LOGIC HIỂN THỊ TRẠNG THÁI THÔNG MINH
          String statusText = "";
          Color statusColor = Colors.white;

          // Hiển thị lỗi giả mạo (Anti-spoofing)
          if (controller.errorMsg.value.isNotEmpty) {
            statusText = controller.errorMsg.value;
            statusColor = Colors.redAccent;
            // Nhắc nhở khoảng cách khuôn mặt
          } else if (controller.faceInstruction.value.isNotEmpty) {
            statusText = controller.faceInstruction.value;
            statusColor = Colors.orangeAccent; // Màu cam cảnh báo
            // Đang quét
          } else if (controller.detectedFaces.isNotEmpty) {
            // 3. Thấy mặt nhưng chưa nhận diện xong/chưa đủ điều kiện
            statusText = "🔍 Đang nhận diện...";
            // 4. Không thấy ai
          } else {
            statusText = "Xin hãy nhìn vào Camera";
          }

          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            decoration: BoxDecoration(
              color: Colors.black54, // Nền đen mờ
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: Colors.white24),
            ),
            child: Text(
              statusText,
              style: TextStyle(
                color: statusColor,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          );
        }),
      ),
    );
  }
}
