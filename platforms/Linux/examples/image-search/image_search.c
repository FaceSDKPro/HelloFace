/*
 * Public C ABI only. Input is tightly packed, orientation-normalized RGBA8888.
 *
 * 仅使用公开 C ABI；输入为方向已归正、紧密排列的 RGBA8888。
 */
#include <hiface/hiface_linux.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int check(HiFaceStatus status, const char *operation) {
    if (status == HIFACE_STATUS_OK) return 1;
    fprintf(stderr, "%s failed: HiFaceStatus=%d\n", operation, (int)status);
    return 0;
}

static unsigned char *read_file(const char *path, size_t maximum, size_t *size) {
    FILE *input = fopen(path, "rb");
    long length;
    unsigned char *bytes = NULL;
    *size = 0;
    if (!input) { perror(path); return NULL; }
    if (fseek(input, 0, SEEK_END) || (length = ftell(input)) <= 0 ||
            (unsigned long)length > maximum || fseek(input, 0, SEEK_SET)) goto done;
    bytes = (unsigned char *)malloc((size_t)length);
    if (!bytes) goto done;
    if (fread(bytes, 1, (size_t)length, input) != (size_t)length) {
        free(bytes); bytes = NULL;
    } else { *size = (size_t)length; }
done:
    fclose(input);
    if (!bytes) fprintf(stderr, "Cannot read file or size limit exceeded: %s\n", path);
    return bytes;
}

static int dimension(const char *text) {
    char *end;
    long value;
    errno = 0;
    value = strtol(text, &end, 10);
    return !errno && *text && !*end && value >= 2 && value <= HIFACE_MAX_IMAGE_DIMENSION ? (int)value : 0;
}

int main(int argc, char **argv) {
    HiFaceSessionHandle session = NULL;
    HiFaceSearchDatabaseHandle database = NULL;
    HiFaceSearchResultsHandle results = NULL;
    unsigned char *rgba = NULL;
    HiFaceConfigV1 config = {0};
    HiFaceRuntimeConfigV1 runtime = {0};
    HiFaceModelLoadReportV1 report = {0};
    HiFaceFaceV1 faces[HIFACE_MAX_FACES];
    HiFaceStatus statuses[HIFACE_MAX_FACES];
    float features[HIFACE_MAX_FACES * HIFACE_FACE_FEATURE_DIMENSION];
    uint32_t count = 0, i;
    int width, height, exit_code = 1;
    size_t size = 0, expected;
    if (argc != 6 || strcmp(argv[1], "--builtin") != 0 || !(width = dimension(argv[4])) || !(height = dimension(argv[5]))) {
        fprintf(stderr, "Usage: %s --builtin DATABASE INPUT.rgba WIDTH HEIGHT\n"
                "Use --blank for INPUT.rgba to run a no-face inference check. Dimensions: 2..4096.\n", argv[0]);
        return 2;
    }
    expected = (size_t)width * (size_t)height * 4;
    if (strcmp(argv[3], "--blank") == 0) {
        rgba = (unsigned char *)calloc(expected, 1); size = expected;
    } else { rgba = read_file(argv[3], expected, &size); }
    if (!rgba || size != expected) { fprintf(stderr, "Expected exactly %zu RGBA bytes\n", expected); goto done; }
    runtime.struct_size = sizeof(runtime);
    runtime.api_version = HIFACE_C_API_VERSION_V1;
    if (!check(hiface_runtime_configure_v1(&runtime), "configure runtime")) goto done;
    config.struct_size = sizeof(config);
    config.api_version = HIFACE_C_API_VERSION_V1;
    config.compute_mode = HIFACE_COMPUTE_CPU;
    config.enable_feature = 1;
    config.enable_landmark = 1;
    config.eye_closed_ear_threshold = HIFACE_DEFAULT_EYE_CLOSED_EAR_THRESHOLD;
    config.mouth_open_mar_threshold = HIFACE_DEFAULT_MOUTH_OPEN_MAR_THRESHOLD;
    if (!check(hiface_session_create_v1(&config, &session), "create session")) goto done;
    report.struct_size = sizeof(report);
    if (!check(hiface_linux_load_builtin_models_v1(session, &report), "initialize SDK models") ||
            !check(hiface_search_open_v1(argv[2], &database), "open database") ||
            !check(hiface_session_capture_faces_rgba_v1(session, rgba, expected, width, height,
                faces, statuses, features, HIFACE_MAX_FACES, &count, NULL, 0), "capture faces")) goto done;
    printf("faces=%u (static images have no liveness gate)\n", count);
    for (i = 0; i < count; ++i) {
        printf("face=%u status=%d\n", i + 1, (int)statuses[i]);
        if (statuses[i] != HIFACE_STATUS_OK) continue; /* Small faces are independent failures. / 过小人脸分别作为独立失败处理。 */
        if (!check(hiface_search_query_v1(database, features + i * HIFACE_FACE_FEATURE_DIMENSION,
                HIFACE_FACE_FEATURE_DIMENSION, NULL, NULL, 1, HIFACE_DEFAULT_VERIFICATION_THRESHOLD,
                &results), "query database")) goto done;
        if (hiface_search_results_count_v1(results)) {
            HiFaceSearchEntryV1 entry = {0};
            float score = 0;
            entry.struct_size = sizeof(entry);
            if (!check(hiface_search_results_get_v1(results, 0, &entry, &score), "read result")) goto done;
            printf("  id=%s similarity=%.6f\n", entry.face_id, (double)score);
            /*
             * Copy entry strings/feature before destroying results if the application retains them.
             *
             * 若应用需要保留条目字符串或特征，应在销毁结果前复制。
             */
        } else { puts("  unmatched (or empty library)"); }
        hiface_search_results_destroy_v1(results); results = NULL;
    }
    exit_code = 0;
done:
    hiface_search_results_destroy_v1(results);
    hiface_search_close_v1(database);
    hiface_session_destroy_v1(session);
    free(rgba);
    return exit_code;
}
