import 'package:flutter/material.dart';
import 'package:get/get.dart';

class RegisterAccountController extends GetxController {
  final usernameController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();

  var isLoading = false.obs;

  void register() async {
    if (passwordController.text != confirmPasswordController.text) {
      Get.snackbar(
        'Lỗi',
        'Mật khẩu xác nhận không khớp!',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red[100],
      );
      return;
    }

    isLoading.value = true;
    // Giả lập gọi API đăng ký
    await Future.delayed(const Duration(seconds: 2));
    isLoading.value = false;

    Get.snackbar(
      'Thành công',
      'Đăng ký thành công, vui lòng đăng nhập',
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: Colors.green[100],
    );

    // Quay lại màn hình Login
    Get.back();
  }

  @override
  void onClose() {
    usernameController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    super.onClose();
  }
}
