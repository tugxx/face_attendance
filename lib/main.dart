import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'app/routes/app_pages.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(
    GetMaterialApp(
      title: "Face Attendance",
      debugShowCheckedModeBanner: false,
      initialRoute: AppPages.initial, // Bắt đầu từ Route này
      getPages: AppPages.routes, // Nạp danh sách routes
      theme: ThemeData.dark(),
    ),
  );
}
