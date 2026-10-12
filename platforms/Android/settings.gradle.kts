pluginManagement {
    repositories {
        // Google 插件仓库优先使用镜像，官方仓库兜底。
        maven("https://maven.aliyun.com/repository/google") {
            content {
                includeGroupByRegex("com\\.android.*")
                includeGroupByRegex("com\\.google.*")
                includeGroupByRegex("androidx.*")
            }
        }
        google {
            content {
                includeGroupByRegex("com\\.android.*")
                includeGroupByRegex("com\\.google.*")
                includeGroupByRegex("androidx.*")
            }
        }
        mavenCentral()
        gradlePluginPortal()
    }
}
plugins {
    id("org.gradle.toolchains.foojay-resolver-convention") version "1.0.0"
}

val sdkRepository = providers.gradleProperty("hiface.sdkRepository")
    .orNull
    ?.trim()
    ?.takeIf(String::isNotEmpty)

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        // Google 依赖仓库优先使用镜像，官方仓库兜底。
        maven("https://maven.aliyun.com/repository/google") {
            content {
                includeGroupByRegex("com\\.android.*")
                includeGroupByRegex("com\\.google.*")
                includeGroupByRegex("androidx.*")
            }
        }
        google()
        // 发布工作流可指向隔离的本地仓库，验证 Demo 确实只消费待发布 AAR。
        sdkRepository?.let { repositoryUrl ->
            maven {
                name = "HiFaceSdkOverride"
                url = uri(repositoryUrl)
                content {
                    includeModule("io.github.facesdkpro", "hiface-android")
                }
            }
        }
        mavenCentral()


    }
}

rootProject.name = "HiFaceAndroid"
include(":demo")
