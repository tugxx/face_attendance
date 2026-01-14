# Bỏ qua cảnh báo về TensorFlow Lite GPU (Cái đang gây lỗi cho bạn)
-dontwarn org.tensorflow.lite.**
-keep class org.tensorflow.lite.** { *; }

# --- 2. Fix lỗi Google Play Core (LỖI BẠN VỪA GẶP) ---
# Bỏ qua cảnh báo thiếu thư viện Split Install/Play Core
-dontwarn com.google.android.play.core.**
-dontwarn io.flutter.embedding.engine.deferredcomponents.**

# Giữ lại các class quan trọng để tránh crash runtime
-keep class com.google.android.play.core.** { *; }

# Giữ lại các class quan trọng của Flutter và plugins
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Fix lỗi Enum generic (thường gặp khi build release)
-keepattributes EnclosingMethod