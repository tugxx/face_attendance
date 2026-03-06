import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:camera/camera.dart';
// import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../controllers/face_register_controller.dart';
import '../widgets/face_overlay_painter.dart';

class FaceRegisterView extends GetView<FaceRegisterController> {
  const FaceRegisterView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Obx(() {
        if (!controller.isInitialized.value ||
            controller.cameraController == null) {
          return const Center(child: CircularProgressIndicator());
        }

        return Stack(
          fit: StackFit.expand,
          children: [
            // 1. Camera
            CameraPreview(controller.cameraController!),

            // 2. Vẽ khung
            SizedBox.expand(
              child: CustomPaint(
                painter: FaceOverlayPainter(
                  borderColor: controller.frameColor.value,
                  progress: controller.scanProgress.value,
                ),
              ),
            ),

            // 3. Layer hướng dẫn (Text: Quay trái, quay phải...)
            Obx(() {
              if (controller.isRegistering.value) {
                return const SizedBox.shrink(); // Đang xử lý thì ẩn đi
              }

              return Positioned(
                bottom: 60,
                left: 20,
                right: 20,
                child: Center(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(
                        color: controller
                            .frameColor
                            .value, // Viền hộp cùng màu với Oval
                        width: 2,
                      ),
                      // Hiệu ứng phát sáng viền cực xịn
                      boxShadow: [
                        BoxShadow(
                          color: controller.frameColor.value.withValues(
                            alpha: 0.4,
                          ),
                          blurRadius: 10,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Text(
                      // Lấy chữ hướng dẫn từ Controller in ra đây
                      controller.faceInstruction.value.isEmpty
                          ? "Đưa khuôn mặt vào khung và làm theo hướng dẫn"
                          : controller.faceInstruction.value,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: controller.frameColor.value == Colors.white70
                            ? Colors.white
                            : controller.frameColor.value,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              );
            }),

            // 4. Loading Overlay (Chỉ hiện khi ĐANG xử lý đăng ký)
            if (controller.isRegistering.value)
              Container(
                color: Colors.black54,
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: Colors.white),
                      SizedBox(height: 20),
                      Text(
                        "Đang xử lý hình ảnh...",
                        style: TextStyle(color: Colors.white, fontSize: 18),
                      ),
                    ],
                  ),
                ),
              ),

            // Nút Back
            Positioned(
              top: 50,
              left: 20,
              child: IconButton(
                icon: const Icon(
                  Icons.arrow_back,
                  color: Colors.white,
                  size: 30,
                ),
                onPressed: () => Get.back(),
              ),
            ),

            // ✅ LAYER 6: DIALOG PHÁT HIỆN TRÙNG LẶP
            Obx(() {
              if (!controller.showDuplicateDialog.value) {
                return const SizedBox.shrink();
              }

              return Container(
                color: Colors.black.withValues(
                  alpha: 0.8,
                ), // Phủ đen toàn màn hình
                child: Center(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 20),
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          "Người Quen!",
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                        ),
                        const SizedBox(height: 15),
                        ClipOval(
                          child: Image.memory(
                            controller.tempDisplayBytes.value,
                            width: 120,
                            height: 120,
                            fit: BoxFit.cover,
                          ),
                        ),
                        const SizedBox(height: 15),
                        Text(
                          "Hệ thống nhận diện:\n${controller.tempRecognizedName.value}",
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Colors.black,
                          ),
                        ),
                        const SizedBox(height: 5),
                        LinearProgressIndicator(
                          value: controller.tempConfidence.value,
                          backgroundColor: Colors.grey[200],
                          color: Colors.green,
                          minHeight: 8,
                        ),
                        Text(
                          "Độ tin cậy: ${(controller.tempConfidence.value * 100).toStringAsFixed(1)}%",
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 20),

                        // NÚT BẤM GỌI VỀ CONTROLLER
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: controller.onUpdateExistingUser,
                            icon: const Icon(Icons.merge_type),
                            label: const Text("Cập nhật thêm dữ liệu"),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: controller.onResetExistingUser,
                            icon: const Icon(Icons.refresh),
                            label: const Text("Ghi đè (Reset)"),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.orange,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: controller.onNotThisPerson,
                          child: const Text(
                            "Không phải, người mới",
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),

            // ✅ LAYER 7: DIALOG ĐĂNG KÝ MỚI
            Obx(() {
              if (!controller.showNewUserDialog.value) {
                return const SizedBox.shrink();
              }

              // Dùng TextEditingController cục bộ ngay tại View
              final nameController = TextEditingController();

              return GestureDetector(
                onTap: () {
                  // Lệnh này sẽ thu hồi Focus, ép bàn phím ảo thụt xuống
                  FocusManager.instance.primaryFocus?.unfocus();
                },
                // Thêm thuộc tính này để đảm bảo bấm vào nền trong suốt vẫn nhận diện được
                behavior: HitTestBehavior.opaque,

                child: Container(
                  color: Colors.black.withValues(alpha: 0.8),
                  child: Center(
                    child: GestureDetector(
                      onTap: () {
                        // Trống: Để khi bấm vào vùng trắng của Dialog thì không bị tắt bàn phím
                      },
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 20),
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              "Đăng Ký Mới",
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.black,
                              ),
                            ),
                            const SizedBox(height: 15),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(50),
                              child: Image.memory(
                                controller.tempDisplayBytes.value,
                                width: 120,
                                height: 120,
                                fit: BoxFit.cover,
                              ),
                            ),
                            const SizedBox(height: 20),

                            TextField(
                              controller: nameController,
                              autofocus: true,
                              style: const TextStyle(color: Colors.black),
                              decoration: const InputDecoration(
                                labelText: "Họ và tên",
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.person),
                                // Ép TextField nhỏ gọn lại
                                isDense: true,
                                // Thu hẹp khoảng cách viền trong của ô nhập liệu
                                contentPadding: EdgeInsets.symmetric(
                                  vertical: 12,
                                  horizontal: 10,
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                TextButton(
                                  onPressed: controller.onCancelDialog,
                                  child: const Text(
                                    "Chụp lại",
                                    style: TextStyle(color: Colors.red),
                                  ),
                                ),
                                ElevatedButton(
                                  onPressed: () => controller.onRegisterNewUser(
                                    nameController.text,
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blue,
                                    foregroundColor: Colors.white,
                                  ),
                                  child: const Text("Lưu"),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ],
        );
      }),
    );
  }
}
