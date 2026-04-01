import 'package:dio/dio.dart';
import 'package:get/get.dart' as getx;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../utils/api_constants.dart';
import '../services/log_service.dart';
import '../../routes/app_routes.dart';

class PerformanceInterceptor extends Interceptor {
  final Map<String, int> _requests = {};

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    // Lưu lại thời gian bắt đầu gọi API bằng mã hash của request
    _requests[options.hashCode.toString()] =
        DateTime.now().millisecondsSinceEpoch;
    super.onRequest(options, handler);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    _logTime(response.requestOptions, response.statusCode);
    super.onResponse(response, handler);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    _logTime(err.requestOptions, err.response?.statusCode);
    super.onError(err, handler);
  }

  void _logTime(RequestOptions options, int? statusCode) {
    final startTime = _requests.remove(options.hashCode.toString());
    if (startTime != null) {
      final duration = DateTime.now().millisecondsSinceEpoch - startTime;
      final method = options.method;
      final path = options.path;

      // Chỉ in ra log nếu thời gian gọi API quá lâu (VD: > 1000ms)
      // Hoặc in ra hết lúc Debug.
      if (duration > 1000) {
        AppLog.warning(
          "🐢 [API SLOW] $method $path - $statusCode tốn: ${duration}ms",
        );
      } else {
        AppLog.info("⚡ [API] $method $path - $statusCode tốn: ${duration}ms");
      }
    }
  }
}

class ApiService {
  late final Dio dio;
  final storage = const FlutterSecureStorage();

  // Khởi tạo Singleton (Dùng chung 1 instance cho toàn app)
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;

  Future<bool> refreshToken() async {
    final refreshToken = await storage.read(key: 'refresh_token');
    if (refreshToken == null) {
      await _forceLogout();
      return false;
    }

    try {
      AppLog.info("🔄 Đang tiến hành Refresh Token...");
      final tokenDio = Dio(BaseOptions(baseUrl: ApiConstants.baseUrl));
      final response = await tokenDio.post(
        ApiConstants.refreshToken, // Thay endpoint của bạn nếu cần
        data: {'refresh': refreshToken},
      );

      if (response.statusCode == 200) {
        await storage.write(
          key: 'access_token',
          value: response.data['access'],
        );
        if (response.data['refresh'] != null) {
          await storage.write(
            key: 'refresh_token',
            value: response.data['refresh'],
          );
        }
        AppLog.info("✅ Đã xin cấp lại Token thành công!");
        return true;
      }
      return false;
    } catch (e) {
      AppLog.error("❌ Refresh Token cũng đã hết hạn hoặc bị lỗi!");
      await _forceLogout();
      return false;
    }
  }

  ApiService._internal() {
    dio = Dio(
      BaseOptions(
        baseUrl: ApiConstants.baseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        headers: {'Content-Type': 'application/json'},
      ),
    );

    // 2. GẮN MÁY ĐO THỜI GIAN VÀO DIO
    dio.interceptors.add(PerformanceInterceptor());

    // THIẾT LẬP TRẠM KIỂM SOÁT (INTERCEPTOR)
    dio.interceptors.add(
      QueuedInterceptorsWrapper(
        // 1. TRƯỚC KHI GỬI REQUEST
        onRequest: (options, handler) async {
          // Bỏ qua việc gắn Token nếu đang gọi API Login hoặc Register
          if (!options.path.contains('/login') &&
              !options.path.contains('/register')) {
            // Mở két lấy Access Token
            final token = await storage.read(key: 'access_token');
            if (token != null) {
              // Dán thẻ vào ngực (Header)
              options.headers['Authorization'] = 'Bearer $token';
            }
          }
          return handler.next(options); // Tiếp tục cho xe chạy
        },

        // 2. KHI NHẬN ĐƯỢC RESPONSE TỪ SERVER
        onResponse: (response, handler) {
          return handler.next(response); // Cứ cho qua bình thường
        },

        // 3. KHI XẢY RA LỖI (Quan trọng nhất là lỗi 401 Hết hạn Token)
        onError: (DioException error, handler) async {
          if (error.response?.statusCode == 401 &&
              !error.requestOptions.path.contains('/login') &&
              !error.requestOptions.path.contains('/token/refresh')) {
            AppLog.error(
              "🚨 Access Token hết hạn! Bắt đầu quá trình xin cấp lại...",
            );

            bool isRefreshed = await refreshToken();

            if (isRefreshed) {
              final newAccessToken = await storage.read(key: 'access_token');
              error.requestOptions.headers['Authorization'] =
                  'Bearer $newAccessToken';
              final cloneReq = await dio.fetch(error.requestOptions);
              return handler.resolve(cloneReq);
            } else {
              return handler.reject(error);
            }
          }
          return handler.next(error);
        },
      ),
    );
  }

  // Hàm đá văng người dùng ra màn hình đăng nhập nếu mọi nỗ lực đều thất bại
  Future<void> _forceLogout() async {
    await storage.deleteAll(); // Xóa sạch token cũ
    getx.Get.snackbar('Phiên đăng nhập hết hạn', 'Vui lòng đăng nhập lại!');
    getx.Get.offAllNamed(Routes.login);
  }
}
