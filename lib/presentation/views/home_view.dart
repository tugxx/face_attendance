import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/home_controller.dart';

class HomeView extends GetView<HomeController> {
  const HomeView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5), // Nền xám nhẹ sáng sủa
      appBar: AppBar(
        title: const Text(
          "Hệ thống Chấm Công",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: Colors.blueAccent,
        elevation: 0,
      ),
      body: Obx(() {
        return Stack(
          children: [
            // --- GIAO DIỆN CHÍNH ---
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    "Chọn chức năng",
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 30),

                  // 1. NÚT ĐĂNG KÝ
                  _buildMenuCard(
                    icon: Icons.person_add_alt_1,
                    title: "Đăng ký Khuôn mặt",
                    subtitle: "Thêm nhân viên mới vào hệ thống",
                    color: Colors.orange,
                    onTap: controller.goToRegister,
                  ),
                  const SizedBox(height: 20),

                  const SizedBox(height: 20),
                  // 3. NÚT CHẤM CÔNG
                  _buildMenuCard(
                    icon: Icons.fact_check,
                    title: "Điểm danh",
                    subtitle: "Chế độ chấm công tự động",
                    color: Colors.green,
                    onTap: controller.goToAttendance,
                  ),
                ],
              ),
            ),

            // --- LỚP OVERLAY LOADING (Chỉ hiện khi isLoadingAI = true) ---
            if (controller.isLoadingAI.value)
              Container(
                color: Colors.black.withValues(
                  alpha: 0.3,
                ), // Màn mờ chặn thao tác
                child: const Center(child: CircularProgressIndicator()),
              ),
          ],
        );
      }),
    );
  }

  Widget _buildMenuCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(15),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 30),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}
