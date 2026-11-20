plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.exam_secret_codes"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.example.exam_secret_codes"
        minSdk = 21
        targetSdk = 36
        multiDexEnabled = true
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            val signingFile = file("exam-secret-codes-release.jks")
            val storePass = System.getenv("ANDROID_STORE_PASSWORD")
            val keyPass = System.getenv("ANDROID_KEY_PASSWORD")
            val keyAliasValue = System.getenv("ANDROID_KEY_ALIAS")
            if (!signingFile.exists() || storePass.isNullOrBlank() ||
                keyPass.isNullOrBlank() || keyAliasValue.isNullOrBlank()) {
                throw GradleException(
                    "Release signing secrets are missing. Configure the four ANDROID_* GitHub Actions secrets."
                )
            }
            storeFile = signingFile
            storePassword = storePass
            keyPassword = keyPass
            keyAlias = keyAliasValue
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("com.tom-roush:pdfbox-android:2.0.27.0")
    implementation("com.google.zxing:core:3.5.3")
}
