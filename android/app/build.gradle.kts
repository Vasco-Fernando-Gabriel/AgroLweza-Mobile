plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.agrolweza.agrolweza_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.agrolweza.agrolweza_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // As dependencias AAR (tensorflow-lite, datastore) trazem .so para ABIs
        // que o build do Flutter nao cobre. Isso cria uma pasta lib/<abi> com
        // libs de terceiros mas SEM libflutter.so/libapp.so: o telemovel elege
        // essa ABI, instala com sucesso e rebenta no arranque com
        // UnsatisfiedLinkError. Fixar as ABIs garante que so existe a pasta de
        // uma ABI que o Flutter tambem preencheu.
        ndk {
            abiFilters += listOf("armeabi-v7a", "arm64-v8a")
        }
    }

    // O abiFilters acima nao chega: o plugin Gradle do Flutter reescreve as ABIs
    // do build, e as .so vindas dos AAR reaparecem. Isto corta no empacotamento.
    packaging {
        jniLibs {
            excludes += setOf("lib/x86/**", "lib/x86_64/**")
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
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

// tflite_flutter traz tensorflow-lite, tensorflow-lite-api e tensorflow-lite-gpu,
// todos com o mesmo namespace "org.tensorflow.lite", o que quebra o manifest
// merger do AGP (namespace duplicado). Nao precisamos do delegate de GPU
// (modelo pequeno, roda bem em CPU) e o artefacto "-api" so contem as
// interfaces ja implementadas dentro do artefacto principal "tensorflow-lite".
configurations.all {
    exclude(group = "org.tensorflow", module = "tensorflow-lite-gpu")
    exclude(group = "org.tensorflow", module = "tensorflow-lite-api")
}
