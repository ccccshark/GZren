# ProGuard / R8 规则 - 蛊真人单机文字MUD
# Flutter release 包默认 AOT 编译 Dart 代码为机器码，ProGuard 仅作用于原生 Android 层。

# 忽略 Play Core 缺失类（纯离线 App 不使用 Play Store 延迟组件）
-dontwarn com.google.android.play.core.**

# Flutter 相关：保留 Flutter 引擎入口和插件接口
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# path_provider / shared_preferences 等插件需保留反射入口
-keep class androidx.** { *; }
-dontwarn androidx.**

# 保留 Application 类（FlutterApplication）
-keep class * extends android.app.Application

# 保留原生方法（JNI 调用）
-keepclasseswithmembernames class * {
    native <methods>;
}

# 保留 Parcelable
-keep class * implements android.os.Parcelable {
    public static final android.os.Parcelable$Creator *;
}
