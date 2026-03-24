# Flutter
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# Go core (JNI / libclash.so)
-keep class com.yueto.yuelink.** { *; }

# media_kit (libmpv JNI)
-keep class com.alexmercerind.** { *; }
-keep class com.alexmercerind.media_kit_video.** { *; }

# Suppress R8 warnings for packages used via reflection
-dontwarn org.bouncycastle.**
-dontwarn org.conscrypt.**
-dontwarn org.openjsse.**
