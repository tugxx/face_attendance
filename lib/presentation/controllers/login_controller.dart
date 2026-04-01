import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../app/services/log_service.dart';
import '../../app/utils/api_constants.dart';
import '../../app/network/api_service.dart';

class LoginController extends GetxController {
  // Quản lý ô nhập liệu
  final usernameController = TextEditingController();
  final passwordController = TextEditingController();

  // Biến trạng thái loading (dùng Obx để cập nhật UI)
  var isLoading = false.obs;

  // Khởi tạo Dio và Két sắt
  final storage = const FlutterSecureStorage();

  Future<String?> login() async {
    if (usernameController.text.isEmpty || passwordController.text.isEmpty) {
      return 'Vui lòng nhập đầy đủ thông tin!';
    }

    isLoading.value = true;

    try {
      // ĐẶT ĐOẠN TEST LÊN ĐẦU: Bypass API nếu đúng tài khoản test
      if (usernameController.text == "tung" &&
          passwordController.text == "123456") {
        await storage.write(key: 'access_token', value: 'test_token_cho_nhanh');
        AppLog.info("Đã bypass login bằng tài khoản test");
        isLoading.value = false; // Nhớ tắt loading
        return null; // Trả về null tức là login thành công
      }

      // 1. BẮN API
      // Thay URL dưới đây bằng cái link TryCloudflare hiện tại của bạn
      final response = await ApiService().dio.post(
        '${ApiConstants.baseUrl}${ApiConstants.login}',
        data: {
          "username": usernameController.text,
          "password": passwordController.text,
        },
      );

      // 2. XỬ LÝ KẾT QUẢ KHI THÀNH CÔNG (Mã 200)
      if (response.statusCode == 200) {
        // Lấy token từ dữ liệu JSON trả về
        final accessToken = response.data['access'];
        final refreshToken = response.data['refresh'];

        // Cất vào két sắt
        await storage.write(key: 'access_token', value: accessToken);
        await storage.write(key: 'refresh_token', value: refreshToken);

        return null;
      }
      return 'Lỗi hệ thống từ server';
    } on DioException catch (e) {
      // 3. XỬ LÝ KHI LỖI (Sai pass, lỗi server...)
      AppLog.error("Lỗi API: ${e.response?.data ?? e.message}");

      // Nếu server có trả về response (tức là có mạng và server đã xử lý)
      if (e.response != null) {
        final statusCode = e.response!.statusCode;

        if (statusCode == 401) {
          return 'Sai tài khoản hoặc mật khẩu!'; // Chuẩn lỗi sai pass của JWT
        } else if (statusCode == 400) {
          // Lỗi 400 thường do gửi thiếu data hoặc sai format.
          // Cố gắng đọc message chi tiết từ server Django nếu có.
          final data = e.response!.data;
          if (data is Map && data.containsKey('detail')) {
            return data['detail']; // VD server trả về: {"detail": "Tài khoản đã bị khóa"}
          }
          return 'Dữ liệu không hợp lệ (Lỗi 400)';
        } else if (statusCode != null && statusCode >= 500) {
          return 'Hệ thống Server đang bảo trì (Lỗi $statusCode). Vui lòng thử lại sau!';
        }
      }

      // Nếu KHÔNG có response (Không kết nối được tới server)
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        return 'Mạng quá yếu hoặc phản hồi chậm. Vui lòng kiểm tra lại 4G/Wifi!';
      } else if (e.type == DioExceptionType.connectionError) {
        return 'Không thể kết nối đến máy chủ. Hãy kiểm tra lại mạng!';
      }

      // Lỗi rơi rớt cuối cùng
      return 'Lỗi không xác định: ${e.message}';
    } finally {
      isLoading.value = false;
    }
  }

  @override
  void onClose() {
    usernameController.dispose();
    passwordController.dispose();
    super.onClose();
  }
}
