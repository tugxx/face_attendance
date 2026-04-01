import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'routes/app_pages.dart';
import 'app/services/log_service.dart';
import 'app/extensions/app_profiler.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppLog.info("⏱️ [DEBUG]: Bắt đầu chạy main()");

  // 1. Khởi tạo Hive một lần duy nhất cho toàn App
  await AppProfiler.measureAsync('Hive init', () async {
    await Hive.initFlutter();
  });

  runApp(
    GetMaterialApp(
      title: "Face Attendance",
      debugShowCheckedModeBanner: false,
      initialRoute: AppPages.initial, // Bắt đầu từ Route này
      getPages: AppPages.routes, // Nạp danh sách routes
      theme: ThemeData.light(),
      themeMode: ThemeMode.light,
    ),
  );
}
