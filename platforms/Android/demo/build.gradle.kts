import java.util.Properties

plugins {
    alias(libs.plugins.android.application)
}

// 本机签名由使用者管理，凭据文件不进入 Git 或客户导出包。
val demoSigningFile = layout.projectDirectory.file("signing.properties").asFile
val demoSigning = Properties().apply {
    if (demoSigningFile.isFile) demoSigningFile.reader(Charsets.UTF_8).use { load(it) }
}

android {
    namespace = "com.hiface.sdk.demo"
    compileSdk = libs.versions.compileSdk.get().toInt()

    defaultConfig {
        applicationId = "com.hiface.sdk.public"
        minSdk = libs.versions.minSdk.get().toInt()
        targetSdk = libs.versions.targetSdk.get().toInt()
        versionCode = 1
        versionName = "0.0.1"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"

        ndk {
            abiFilters += listOf("arm64-v8a", "armeabi-v7a")
        }
    }

    //打包签名，  接入方请使用自己的签名配置
    signingConfigs {
        if (demoSigningFile.isFile) {
            create("release") {
                fun signingValue(name: String): String =
                    requireNotNull(demoSigning.getProperty(name)?.takeIf { it.isNotEmpty() }) {
                        "demo/signing.properties 缺少 $name"
                    }
                storeFile = file(signingValue("storeFile"))
                storePassword = signingValue("storePassword")
                keyAlias = signingValue("keyAlias")
                keyPassword = signingValue("keyPassword")
            }
        }
    }

    buildTypes {
        debug {
            isDebuggable = true
        }
        release {
            // Release 裁剪无用代码与资源，JNI 保留规则由 SDK 随 AAR 提供。
            isMinifyEnabled = true
            isShrinkResources = true
            signingConfig = signingConfigs.findByName("release")
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
    // 压缩 APK 内的 .so，安装时解压，减小 APK 体积。
    packaging.jniLibs.useLegacyPackaging = true
    androidResources {
        // 模型必须保持未压缩供 Native mmap；AAR 的 noCompress 不会传递给宿主应用。
        noCompress += "bphfm"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        // 避免构建机默认字符集影响中文字符串。
        encoding = "UTF-8"
    }
}

dependencies {
    implementation("io.github.facesdkpro:hiface-android:0.0.1")

    implementation(libs.androidx.core)
    implementation(libs.androidx.activity)
    implementation(libs.androidx.appcompat)
    implementation(libs.androidx.recyclerview)
    implementation(libs.androidx.fragment)
    implementation(libs.androidx.constraintlayout)
    implementation(libs.material)

    // CameraX 只负责相机采集，人脸算法由 SDK 提供。
    implementation(libs.androidx.camera.view)
    implementation(libs.androidx.camera.camera2)
    implementation(libs.androidx.camera.lifecycle)
    // 仅 Demo 保存 1:1 人脸特征与相机设置。
    implementation(libs.mmkv)

    testImplementation(libs.junit)
    androidTestImplementation(libs.androidx.test.runner)
    androidTestImplementation(libs.androidx.test.junit)
}
