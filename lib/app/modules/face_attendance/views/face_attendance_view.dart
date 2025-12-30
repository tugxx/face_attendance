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

      // --- NÚT ĐĂNG KÝ (Floating Action Button) ---
      // Sửa lỗi sort_child_properties_last: child để cuối cùng
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showRegisterDialog(controller),
        backgroundColor: Colors.blue,
        child: const Icon(Icons.add_a_photo),
      ),

      body: Obx(() {
        // 1. Xử lý lỗi
        if (controller.errorMsg.value.isNotEmpty) {
          return Center(
            child: Text(
              controller.errorMsg.value,
              style: const TextStyle(color: Colors.red),
              textAlign: TextAlign.center,
            ),
          );
        }

        // 2. Chờ khởi tạo
        if (!controller.isInitialized.value ||
            controller.cameraController == null) {
          return const Center(child: CircularProgressIndicator());
        }

        // 3. Hiển thị Camera
        final camera = controller.cameraController!.value;
        final Size imageSize = Size(
          camera.previewSize?.height ?? 0,
          camera.previewSize?.width ?? 0,
        );

        return Stack(
          fit: StackFit.expand,
          children: [
            CameraPreview(controller.cameraController!),

            // Layer vẽ khung
            if (controller.detectedFaces.isNotEmpty)
              CustomPaint(
                painter: FaceDetectorPainter(
                  // Đảm bảo bạn có class này
                  controller.detectedFaces.toList(),
                  imageSize,
                  InputImageRotation
                      .rotation0deg, // Cần cẩn thận chỗ này (Android thường là 90 hoặc 270)
                  CameraLensDirection.front,
                ),
              ),

            // Layer UI điều khiển (Nút back, trạng thái text...)
            _buildOverlayUI(),
          ],
        );
      }),
    );
  }

  void _showRegisterDialog(FaceAttendanceController controller) {
    final TextEditingController nameController = TextEditingController();
    
    Get.defaultDialog(
      title: "Đăng ký khuôn mặt",
      titleStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
      content: Column(
        children: [
          const Icon(Icons.face, size: 50, color: Colors.blue),
          const SizedBox(height: 10),
          const Text("Giữ khuôn mặt trong khung hình\nvà nhập tên bên dưới:", textAlign: TextAlign.center),
          const SizedBox(height: 15),
          TextField(
            controller: nameController,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: "Nhập tên nhân viên",
              prefixIcon: Icon(Icons.person),
            ),
          ),
        ],
      ),
      textConfirm: "Lưu",
      textCancel: "Hủy",
      confirmTextColor: Colors.white,
      onConfirm: () {
        if (nameController.text.trim().isNotEmpty) {
          // Gọi hàm đăng ký trong controller
          controller.registerCurrentFace(nameController.text.trim());
          Get.back();
        } else {
          Get.snackbar("Lỗi", "Vui lòng nhập tên", snackPosition: SnackPosition.BOTTOM);
        }
      },
    );
  }

  Widget _buildOverlayUI() {
    return Positioned(
      bottom: 80,
      left: 20,
      right: 20,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.black54, // Nền đen mờ
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: Colors.white24), // Viền nhẹ cho đẹp
          ),
          child: Obx(() {
            // LOGIC HIỂN THỊ TRẠNG THÁI THÔNG MINH
            String statusText = "";
            Color statusColor = Colors.white;

            if (controller.isProcessing.value) {
              // 1. Đang chạy TFLite (Máy đang tính toán)
              statusText = "⏳ Đang xử lý AI...";
              statusColor = Colors.yellowAccent;
            } else if (controller.recognizedName.value != "Unknown") {
              // 2. Đã nhận diện ra tên
              statusText = "✅ Xin chào: ${controller.recognizedName.value}";
              statusColor = Colors.greenAccent;
            } else if (controller.detectedFaces.isNotEmpty) {
              // 3. Thấy mặt nhưng chưa nhận diện xong/chưa đủ điều kiện
              statusText = "🔍 Đang nhận diện...";
            } else {
              // 4. Không thấy ai
              statusText = "Xin hãy nhìn vào Camera";
            }

            return Text(
              statusText,
              style: TextStyle(
                color: statusColor,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            );
          }),
        ),
      ),
    );
  }
}
