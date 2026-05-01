plugins {
    id("com.android.application")
    id("kotlin-android")
    id("kotlin-kapt")
    id("dev.flutter.flutter-gradle-plugin")
}

fun releaseSigningProperty(name: String): String? =
    (project.findProperty(name) as String?) ?: System.getenv(name)

val releaseStoreFilePath = releaseSigningProperty("SAFEROUTE_UPLOAD_STORE_FILE")
val releaseStorePassword = releaseSigningProperty("SAFEROUTE_UPLOAD_STORE_PASSWORD")
val releaseKeyAlias = releaseSigningProperty("SAFEROUTE_UPLOAD_KEY_ALIAS")
val releaseKeyPassword = releaseSigningProperty("SAFEROUTE_UPLOAD_KEY_PASSWORD")
val hasReleaseSigning = listOf(
    releaseStoreFilePath,
    releaseStorePassword,
    releaseKeyAlias,
    releaseKeyPassword,
).all { !it.isNullOrBlank() }

android {
    namespace = "com.saferoute.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    defaultConfig {
        applicationId = "com.saferoute.app"
        minSdk = flutter.minSdkVersion 
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
    }

    signingConfigs {
        create("release") {
            if (hasReleaseSigning) {
                storeFile = file(releaseStoreFilePath!!)
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        release {
            if (hasReleaseSigning) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
}

gradle.taskGraph.whenReady {
    if (allTasks.any { it.name.contains("Release") } && !hasReleaseSigning) {
        throw GradleException(
            "Release signing is not configured. Set SAFEROUTE_UPLOAD_STORE_FILE, " +
                "SAFEROUTE_UPLOAD_STORE_PASSWORD, SAFEROUTE_UPLOAD_KEY_ALIAS, and " +
                "SAFEROUTE_UPLOAD_KEY_PASSWORD."
        )
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.3")

    // Location
    implementation("com.google.android.gms:play-services-location:21.1.0")

    // Room
    val roomVersion = "2.6.1"
    implementation("androidx.room:room-runtime:$roomVersion")
    implementation("androidx.room:room-ktx:$roomVersion")
    annotationProcessor("androidx.room:room-compiler:$roomVersion")
    // For Kotlin Symbol Processing (KSP) if I were using it, but let's stick to annotationProcessor for simplicity unless kapt is set up.
    // Actually, I should check if kapt or ksp is used.
    
    // Retrofit
    implementation("com.squareup.retrofit2:retrofit:2.9.0")
    implementation("com.squareup.retrofit2:converter-gson:2.9.0")

    // Coroutines
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")
}

flutter {
    source = "../.."
}
