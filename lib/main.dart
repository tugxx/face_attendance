// import 'package:face_attendance/app/services/log_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'app/config/app_pages.dart';

void main() {
  // final stopwatch = Stopwatch()..start();

  WidgetsFlutterBinding.ensureInitialized();
  // AppLog.info("⏱️ [DEBUG]: Bắt đầu chạy main()");

  runApp(
    GetMaterialApp(
      title: "Face Attendance",
      debugShowCheckedModeBanner: false,
      initialRoute: AppPages.initial, // Bắt đầu từ Route này
      getPages: AppPages.routes, // Nạp danh sách routes
      theme: ThemeData.dark(),
    ),
  );

  // stopwatch.stop();
  // AppLog.info(
  //   "⏱️ [DEBUG]: Gọi runApp xong tốn tổng cộng: ${stopwatch.elapsedMilliseconds} ms",
  // );
}
