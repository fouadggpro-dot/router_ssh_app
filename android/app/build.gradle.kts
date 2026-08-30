plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    ndkVersion = "28.2.13676358"
    namespace = "com.example.router_controller"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.example.router_controller"
        minSdk = 21
        targetSdk = 36
        versionCode = 1
        versionName = "1.0.0"
    }

    buildTypes {
        getByName("release") {
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }

    compileOptions {
        // تفعيل ميزة Desugaring لدعم التوافق مع المكتبات الحديثة
        isCoreLibraryDesugaringEnabled = true

        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }
}

flutter {
    source = "../.."
}

dependencies {
    // مكتبة Desugaring المطلوبة لـ flutter_local_notifications
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")

    implementation("org.jetbrains.kotlin:kotlin-stdlib-jdk8")
    implementation("com.jcraft:jsch:0.1.55")
}