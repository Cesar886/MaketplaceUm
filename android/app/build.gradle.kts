import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // Add the Google services Gradle plugin
    id("com.google.gms.google-services")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

// key.properties and the .jks are gitignored (they must never be committed), so a fresh
// clone or another machine has no keystore. Only release builds care: fail there with a
// message that says what to restore, instead of shipping an APK signed with a different
// key that no existing tester can upgrade into.
val esTareaDeRelease = gradle.startParameter.taskNames.any { it.contains("Release", ignoreCase = true) }
if (esTareaDeRelease && !keystorePropertiesFile.exists()) {
    throw GradleException(
        "Falta android/key.properties. El APK/AAB de release TIENE que firmarse con " +
        "android/upload-keystore.jks (alias 'upload'): es la firma que ya tienen " +
        "instalada los testers. Restaura key.properties y el .jks desde tu respaldo " +
        "antes de compilar release."
    )
}

android {
    namespace = "site.marketplaceum.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "site.marketplaceum.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        // The config is always declared, even with no key.properties on disk, so that a
        // debug build on a fresh clone still configures. Whether it is actually usable is
        // checked below, and only for the builds that need it.
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = rootProject.file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // Signed with the persistent upload keystore (android/upload-keystore.jks) so
            // every build shares the same signature and installs as an update, not a fresh app.
            //
            // Falling back to the debug key here would be silent and poisonous: the APK
            // still builds, but it carries a different signature, and every tester that
            // already has the app gets "conflicto con un paquete existente" and has to
            // uninstall. That is exactly what happened to every APK built before the
            // release signingConfig existed. So a release build with no key.properties
            // now fails loudly instead of producing an APK nobody can upgrade into.
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")

    // Import the Firebase BoM
    implementation(platform("com.google.firebase:firebase-bom:34.16.0"))

    // Add the dependencies for Firebase products you want to use
    // When using the BoM, don't specify versions in Firebase dependencies
    // https://firebase.google.com/docs/android/setup#available-libraries
}
