# Flutter Engine & Embedding
-keep class io.flutter.** { *; }
-keepclassmembers class io.flutter.** { *; }
-keep class com.routercontroller.agent.** { *; }

# JSch SSH Library
-keep class com.jcraft.jsch.** { *; }
-dontwarn com.jcraft.jsch.**

# Kotlin Coroutines
-keep class kotlinx.coroutines.** { *; }
-keepclassmembers class kotlinx.coroutines.** { *; }