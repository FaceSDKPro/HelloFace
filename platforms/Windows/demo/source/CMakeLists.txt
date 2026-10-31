cmake_minimum_required(VERSION 3.22.1)
if(CMAKE_SOURCE_DIR STREQUAL CMAKE_CURRENT_SOURCE_DIR)
    project(HiFaceWindowsDemo LANGUAGES C CXX RC)
    # Consume the installed public C ABI; release packaging independently pins
    # 接入已安装的公开 C ABI，发布打包流程单独固定 SDK 二进制清单。
    # the reviewed SDK binary catalog instead of a private development tag.
    # 固定的是已审查 SDK 二进制，而不是私有开发标签。
    find_package(HiFace CONFIG REQUIRED COMPONENTS C)
    # Demo-owned integration sample. The SDK itself ships no implementation sources.
    # 由 Demo 持有的接入示例；SDK 本身不交付实现源码。
    set(HIFACE_CPP_INCLUDE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/integration/include")
    add_subdirectory(integration)
endif()
if(HiFace_VERSION)
    set(hiface_demo_sdk_version "${HiFace_VERSION}")
else()
    set(hiface_demo_sdk_version "${HIFACE_WINDOWS_VERSION}")
endif()
if(NOT hiface_demo_sdk_version)
    message(FATAL_ERROR "The Demo requires the linked HiFace SDK version")
endif()
add_library(hiface_windows_demo_support STATIC demo_service.cpp image_search.cpp data_exchange.cpp self_test.cpp win_util.cpp)
target_compile_features(hiface_windows_demo_support PUBLIC cxx_std_17)
target_compile_definitions(hiface_windows_demo_support PUBLIC
    UNICODE _UNICODE NOMINMAX WIN32_LEAN_AND_MEAN _WIN32_WINNT=0x0A00)
if(MSVC)
    target_compile_options(hiface_windows_demo_support PUBLIC /utf-8 /EHsc)
else()
    target_compile_options(hiface_windows_demo_support PRIVATE -Wall -Wextra -Werror)
endif()
target_link_libraries(hiface_windows_demo_support PUBLIC HiFace::Cpp ole32 windowscodecs shell32 uuid comdlg32)
target_include_directories(hiface_windows_demo_support PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}")
enable_language(RC)
if(BUILD_TESTING AND NOT CMAKE_CROSSCOMPILING AND EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/tests/search_power_test.cpp")
    add_executable(hiface_windows_search_power_test tests/search_power_test.cpp)
    target_compile_features(hiface_windows_search_power_test PRIVATE cxx_std_17)
    target_include_directories(hiface_windows_search_power_test PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}")
    add_test(NAME hiface_windows_search_power_test COMMAND hiface_windows_search_power_test)
endif()
add_executable(hiface_demo WIN32 main.cpp app.cpp camera.cpp camera_preferences.cpp theme.cpp image_search_view.cpp)
target_compile_definitions(hiface_demo PRIVATE HIFACE_DEMO_SDK_VERSION="${hiface_demo_sdk_version}")
if(MSVC)
    target_sources(hiface_demo PRIVATE app.manifest)
else()
    target_sources(hiface_demo PRIVATE app.rc)
    set_property(SOURCE app.rc APPEND PROPERTY OBJECT_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/app.manifest")
endif()
target_link_libraries(hiface_demo PRIVATE hiface_windows_demo_support
    mfplat mfreadwrite mfuuid mf user32 gdi32 shell32 comctl32 uxtheme uuid)
add_executable(hiface_cli cli.cpp)
target_link_libraries(hiface_cli PRIVATE hiface_windows_demo_support)
foreach(app hiface_demo hiface_cli)
    if(MSVC)
        target_link_options(${app} PRIVATE "/PDBALTPATH:${app}.pdb")
    endif()
    if(MINGW)
        target_link_options(${app} PRIVATE -municode)
        target_compile_options(${app} PRIVATE -Wall -Wextra -Werror)
    endif()
    set_target_properties(${app} PROPERTIES
        RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin/$<CONFIG>")
endforeach()
if(HiFace_RUNTIME_DIR)
    file(GLOB hiface_runtime_dlls "${HiFace_RUNTIME_DIR}/*.dll")
    # Both consumers share one output directory. One asset target avoids two
    # 两个接入程序共用输出目录；使用同一资源目标，避免两个复制进程并发执行。
    # parallel copy processes racing over the same DLL on Windows.
    # 避免 Windows 上并行复制同一个 DLL 产生竞争。
    set(hiface_example_bin "${CMAKE_BINARY_DIR}/bin/$<CONFIG>")
    add_custom_target(hiface_windows_example_assets
        COMMAND "${CMAKE_COMMAND}" -E make_directory "${hiface_example_bin}"
        COMMAND "${CMAKE_COMMAND}" -E copy_if_different ${hiface_runtime_dlls} "${hiface_example_bin}" VERBATIM)
    foreach(sample features_10000.json images_1000.json)
        add_custom_command(TARGET hiface_windows_example_assets POST_BUILD
            COMMAND "${CMAKE_COMMAND}" -E make_directory "${hiface_example_bin}/data"
            COMMAND "${CMAKE_COMMAND}" -E copy_if_different "${CMAKE_CURRENT_SOURCE_DIR}/../data/${sample}" "${hiface_example_bin}/data/${sample}" VERBATIM)
    endforeach()
    add_dependencies(hiface_demo hiface_windows_example_assets)
    add_dependencies(hiface_cli hiface_windows_example_assets)
endif()

if(NOT CMAKE_SOURCE_DIR STREQUAL CMAKE_CURRENT_SOURCE_DIR)
    install(TARGETS hiface_demo hiface_cli RUNTIME DESTINATION bin COMPONENT Demo)
    install(DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/" DESTINATION source COMPONENT Demo
        PATTERN "README.md" EXCLUDE PATTERN "tests" EXCLUDE)
    install(FILES "${CMAKE_CURRENT_SOURCE_DIR}/README.md" DESTINATION . COMPONENT Demo)
    install(DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/../package/" DESTINATION . COMPONENT Demo)
    install(FILES "${CMAKE_CURRENT_SOURCE_DIR}/../../shared/packaging/sign_product.py" DESTINATION tools COMPONENT Demo)
    install(DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/../sdk/src/" DESTINATION source/integration COMPONENT Demo)
    install(DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/../sdk/include/" DESTINATION source/integration/include COMPONENT Demo
        FILES_MATCHING PATTERN "*.hpp")
    install(FILES "${CMAKE_CURRENT_SOURCE_DIR}/../sdk/cpp/CMakeLists.txt" DESTINATION source/integration COMPONENT Demo)
    install(FILES "${CMAKE_CURRENT_SOURCE_DIR}/../../android/demo/src/main/assets/face_search/features_10000.json"
        "${CMAKE_CURRENT_SOURCE_DIR}/../../android/demo/src/main/assets/face_search/images_1000.json" DESTINATION data COMPONENT Demo)
endif()
