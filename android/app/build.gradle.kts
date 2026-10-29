import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// The release key, from the environment (CI) or android/key.properties (a
// local machine). Neither is in the repository. Without one, release builds
// fall back to the debug key so `flutter build apk` keeps working — but such a
// build cannot update an install signed with the real key, which is why CI
// checks the signature of what it ships.
val releaseSigning: Map<String, String>? = run {
    val env = System.getenv()
    if (!env["FERRY_KEYSTORE"].isNullOrEmpty()) {
        return@run mapOf(
            "storeFile" to env.getValue("FERRY_KEYSTORE"),
            "storePassword" to env["FERRY_KEYSTORE_PASSWORD"].orEmpty(),
            "keyAlias" to env["FERRY_KEY_ALIAS"].orEmpty(),
            "keyPassword" to env["FERRY_KEY_PASSWORD"].orEmpty(),
        )
    }
    val file = rootProject.file("key.properties")
    if (!file.exists()) return@run null
    val props = Properties().apply { file.inputStream().use(::load) }
    listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
        .associateWith { props.getProperty(it).orEmpty() }
}

android {
    namespace = "com.wildalley.ferry"
    compileSdk = flutter.compileSdkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.wildalley.ferry"
        // libbox needs API 24+ for the VpnService/file APIs it relies on.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion

        ndk {
            // libs/libbox.aar is built for arm64 only, so anything else would
            // ship without libbox.so. This only constrains libraries AGP itself
            // packages, though — Flutter's libflutter.so/libapp.so arrive as a
            // Maven dependency and ignore it, so a plain `flutter build apk`
            // still produces armeabi-v7a and x86_64 splits that crash on start.
            // Pass `--target-platform android-arm64` to keep them out; see README.
            abiFilters += "arm64-v8a"
        }
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        releaseSigning?.let { key ->
            create("release") {
                storeFile = file(key.getValue("storeFile"))
                storePassword = key.getValue("storePassword")
                keyAlias = key.getValue("keyAlias")
                keyPassword = key.getValue("keyPassword")
            }
        }
    }

    buildTypes {
        debug {
            // Installs beside a release build instead of over it: a release
            // signed elsewhere cannot be updated by this machine's debug key,
            // and replacing it would mean uninstalling — and losing its data.
            applicationIdSuffix = ".debug"
        }
        release {
            signingConfig = signingConfigs.findByName("release")
                ?: signingConfigs.getByName("debug")
            // libbox's Java bindings are reached by name from Go through JNI, so
            // code shrinking risks stripping live classes. Resource shrinking must
            // be disabled alongside it (AGP rejects one without the other).
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }

    packaging {
        jniLibs {
            // libbox.so is large; keeping it uncompressed lets the loader mmap it.
            useLegacyPackaging = false
            // libbox exists for arm64 only, so other ABIs can never run. The
            // QR scanner's bundled ML Kit still ships its native barcode
            // library for them — about 9 MB that only ever sat in the APK.
            excludes += setOf("lib/x86_64/**", "lib/x86/**", "lib/armeabi-v7a/**")
        }
    }
}

dependencies {
    implementation(files("libs/libbox.aar"))
    implementation("androidx.core:core-ktx:1.15.0")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
