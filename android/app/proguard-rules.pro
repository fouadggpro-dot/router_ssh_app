# JSch and BouncyCastle use reflection internally; without these
# rules R8 strips classes it can't see referenced statically and the
# release build throws ClassNotFoundException at the SSH handshake.
-keep class com.jcraft.jsch.** { *; }
-keep class org.bouncycastle.** { *; }
-dontwarn com.jcraft.jsch.**
-dontwarn org.bouncycastle.**
