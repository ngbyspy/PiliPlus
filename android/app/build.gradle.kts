import com.android.build.gradle.internal.api.ApkVariantOutputImpl
import org.jetbrains.kotlin.konan.properties.Properties
import groovy.json.JsonSlurper

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("org.jetbrains.kotlin.plugin.compose")
}

val agpMajorVersion = com.android.Version.ANDROID_GRADLE_PLUGIN_VERSION
    .substringBefore('.')
    .toInt()
val builtInKotlinProperty = providers.gradleProperty("android.builtInKotlin").orNull
val isBuiltInKotlinEnabled = agpMajorVersion >= 9 &&
        (builtInKotlinProperty == null || builtInKotlinProperty.toBoolean())
if (!isBuiltInKotlinEnabled) {
    apply(plugin = "org.jetbrains.kotlin.android")
}

val spyRelease = JsonSlurper().parse(file("../../tool/spy/release.json")) as Map<*, *>
val spyAcceptance = project.findProperty("spyAcceptance")?.toString() == "true"
val spyImpeller = project.findProperty("spyImpeller")?.toString() == "true"
require(!spyImpeller || spyAcceptance || spyRelease["androidRenderer"] == "impeller") {
    "Formal Impeller builds require the accepted renderer in release policy"
}

android {
    namespace = "com.example.piliplus"
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        manifestPlaceholders["spyEnableImpeller"] = spyImpeller.toString()
        applicationId = spyRelease["androidApplicationId"] as String
        minSdk = flutter.minSdkVersion
        targetSdk = 37
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    packagingOptions.jniLibs.useLegacyPackaging = true

    val keyProperties = Properties().also {
        val properties = rootProject.file(System.getenv("PILIPLUS_SPY_KEY_PROPERTIES") ?: "key.properties")
        if (properties.exists())
            it.load(properties.inputStream())
    }

    val config = keyProperties.getProperty("storeFile")?.let {
        signingConfigs.create("release") {
            storeFile = file(it)
            storePassword = keyProperties.getProperty("storePassword")
            keyAlias = keyProperties.getProperty("keyAlias")
            keyPassword = keyProperties.getProperty("keyPassword")
            enableV1Signing = true
            enableV2Signing = true
        }
    }

    if (gradle.startParameter.taskNames.any { it.contains("Release", ignoreCase = true) } && config == null && !spyAcceptance) {
        error("SPY release signing key is missing. Build through tool/spy/build.ps1 with the preserved signing identity.")
    }

    buildFeatures {
        compose = true
        resValues = true
        if (project.hasProperty("dev")) {
            resValues = true
        }
    }

    buildTypes {
        all {
            resValue("bool", "spy_native_kyant", spyAcceptance.toString())
            signingConfig = if (spyAcceptance) signingConfigs["debug"] else config ?: signingConfigs["debug"]
        }
        release {
            // SPY currently distributes an ARM64 APK; native dependency JARs
            // also contain other ABIs without a matching Flutter application.
            ndk {
                abiFilters += "arm64-v8a"
            }
            if (spyAcceptance) {
                // Keep the existing acceptance installation and key. The
                // suffix identifies the app; it does not select Debug mode.
                applicationIdSuffix = ".debug"
                resValue("string", "app_name", "PiliPlus SPY dev")
            } else if (project.hasProperty("dev")) {
                applicationIdSuffix = ".dev"
                resValue(
                    type = "string",
                    name = "app_name",
                    value = "PiliPlus SPY dev",
                )
            }
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
        debug {
            signingConfig = signingConfigs["debug"]
            applicationIdSuffix = ".debug"
            resValue("string", "app_name", "PiliPlus SPY debug")
            ndk {
                abiFilters += "arm64-v8a"
            }
        }
        if (spyAcceptance) {
            maybeCreate("profile").apply {
                // Keep Flutter's Profile pipeline. Cloning Release also makes
                // plugin libraries obfuscate independently, producing duplicate
                // a.a classes under the current Flutter/AGP combination.
                isMinifyEnabled = false
                isShrinkResources = false
                ndk { abiFilters += "arm64-v8a" }
                signingConfig = signingConfigs["debug"]
                applicationIdSuffix = ".debug"
                isDebuggable = false
                resValue("string", "app_name", "PiliPlus SPY dev")
                matchingFallbacks += "release"
            }
        }
    }

    applicationVariants.all {
        val variant = this
        variant.outputs.forEach { output ->
            (output as ApkVariantOutputImpl).versionCodeOverride = flutter.versionCode
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

// Experimental only on spy/dev. The preserved Flutter renderer remains in use.
dependencies {
    implementation("io.github.kyant0:backdrop:2.0.1")
    implementation("io.github.kyant0:shapes:1.2.1")
    implementation("org.jetbrains.compose.foundation:foundation:1.12.0")
    implementation("org.jetbrains.compose.ui:ui:1.12.0")
}
