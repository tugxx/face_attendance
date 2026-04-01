import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/login_controller.dart';
import '../../routes/app_routes.dart';

class LoginView extends GetView<LoginController> {
  const LoginView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        // Center để giữ form ở giữa màn hình
        child: Center(
          // Bọc SingleChildScrollView để cho phép cuộn khi bàn phím trồi lên
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.face_retouching_natural,
                    size: 80,
                    color: Colors.blue,
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Hệ Thống Điểm Danh',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 40),

                  // Ô nhập Username
                  TextField(
                    controller: controller.usernameController,
                    decoration: const InputDecoration(
                      labelText: 'Tên đăng nhập',
                      prefixIcon: Icon(Icons.person),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Ô nhập Password
                  TextField(
                    controller: controller.passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Mật khẩu',
                      prefixIcon: Icon(Icons.lock),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Nút Đăng nhập (Có hiệu ứng Loading nhờ Obx)
                  Obx(
                    () => ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: controller.isLoading.value
                          ? null
                          : () async {
                              // Chờ Controller xử lý và lấy kết quả
                              final errorMessage = await controller.login();

                              // Xử lý UI dựa trên kết quả
                              if (errorMessage == null) {
                                // THÀNH CÔNG: Hiển thị snackbar xanh và chuyển trang
                                Get.snackbar(
                                  'Thành công',
                                  'Đăng nhập thành công!',
                                  backgroundColor: Colors.green[100],
                                  snackPosition: SnackPosition.TOP,
                                  margin: const EdgeInsets.all(16),
                                );
                                Get.offAllNamed(Routes.home);
                              } else {
                                // THẤT BẠI: Hiển thị snackbar đỏ kèm câu báo lỗi từ Controller
                                Get.snackbar(
                                  'Đăng nhập thất bại',
                                  errorMessage,
                                  backgroundColor: Colors.red[100],
                                  snackPosition: SnackPosition.TOP,
                                  margin: const EdgeInsets.all(16),
                                  icon: const Icon(
                                    Icons.error,
                                    color: Colors.red,
                                  ),
                                );
                              }
                            },
                      child: controller.isLoading.value
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text(
                              'ĐĂNG NHẬP',
                              style: TextStyle(fontSize: 16),
                            ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Nút chuyển sang Đăng ký
                  TextButton(
                    onPressed: () => Get.toNamed(Routes.register),
                    child: const Text('Chưa có tài khoản? Đăng ký ngay'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
