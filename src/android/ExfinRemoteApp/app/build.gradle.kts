import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

fun signingValue(envName: String, propName: String): String? {
    val fromEnv = System.getenv(envName)
    if (!fromEnv.isNullOrBlank()) return fromEnv
    val file = rootProject.file("keystore.properties")
    if (!file.exists()) return null
    val props = Properties()
    file.inputStream().use { props.load(it) }
    return props.getProperty(propName)?.takeIf { it.isNotBlank() }
}

android {
    namespace = "com.exfin.remoteapp"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.exfin.remoteapp"
        minSdk = 26
        targetSdk = 35
        versionCode = 117
        versionName = "1.1.6"
        vectorDrawables.useSupportLibrary = true
    }

    val ksFile = signingValue("EXFIN_KEYSTORE_FILE", "storeFile")
    val ksPass = signingValue("EXFIN_KEYSTORE_PASSWORD", "storePassword")
    val ksAlias = signingValue("EXFIN_KEY_ALIAS", "keyAlias")
    val ksKeyPass = signingValue("EXFIN_KEY_PASSWORD", "keyPassword")
    val canSign = !ksFile.isNullOrBlank() &&
        !ksPass.isNullOrBlank() &&
        !ksAlias.isNullOrBlank() &&
        !ksKeyPass.isNullOrBlank() &&
        file(ksFile!!).isFile
    val sideloadKs = rootProject.file("sideload.jks")
    signingConfigs {
        create("sideload") {
            storeFile = sideloadKs
            storePassword = "android"
            keyAlias = "androiddebugkey"
            keyPassword = "android"
            enableV1Signing = true
            enableV2Signing = true
            enableV3Signing = true
        }
        if (canSign) {
            create("release") {
                storeFile = file(ksFile!!)
                storePassword = ksPass!!
                keyAlias = ksAlias!!
                keyPassword = ksKeyPass!!
                enableV1Signing = true
                enableV2Signing = true
                enableV3Signing = true
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            signingConfig = when {
                canSign -> signingConfigs.getByName("release")
                sideloadKs.isFile -> signingConfigs.getByName("sideload")
                else -> signingConfigs.getByName("debug")
            }
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
        debug {
            versionNameSuffix = "-debug"
            signingConfig = if (sideloadKs.isFile) {
                signingConfigs.getByName("sideload")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }
    buildFeatures {
        compose = true
        buildConfig = true
    }
    composeOptions {
        kotlinCompilerExtensionVersion = "1.5.14"
    }
    packaging {
        resources.excludes += "/META-INF/{AL2.0,LGPL2.1}"
    }
}

dependencies {
    val composeBom = platform("androidx.compose:compose-bom:2024.10.01")
    implementation(composeBom)
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.7")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.8.7")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.8.7")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    debugImplementation("androidx.compose.ui:ui-tooling")
}
