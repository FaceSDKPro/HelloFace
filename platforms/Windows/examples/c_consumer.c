/* Minimal C consumer: configure the runtime, create a session, and query a database.
 * 最小 C 接入示例：配置运行时、创建会话并查询人脸库。 */
#include "hiface/hiface_c_api.h"
#include <stdio.h>

#define REQUIRE(condition) do { if (!(condition)) { \
    fprintf(stderr, "C consumer failed at line %d\n", __LINE__); return 1; \
} } while (0)

int main(void) {
    REQUIRE(hiface_session_search_copy_jpeg_v1(NULL, NULL, NULL, NULL) == HIFACE_STATUS_INVALID_ARGUMENT);
    HiFaceRuntimeConfigV1 runtime = {0};
    runtime.struct_size = sizeof(runtime);
    runtime.api_version = HIFACE_C_API_VERSION;
    REQUIRE(hiface_runtime_configure_v1(&runtime) == HIFACE_STATUS_OK);
    REQUIRE(hiface_get_api_version_v1() == HIFACE_C_API_VERSION);

    HiFaceConfigV1 config = {0};
    config.struct_size = sizeof(config);
    config.api_version = HIFACE_C_API_VERSION;
    config.compute_mode = HIFACE_COMPUTE_CPU;
    config.eye_closed_ear_threshold = HIFACE_DEFAULT_EYE_CLOSED_EAR_THRESHOLD;
    config.mouth_open_mar_threshold = HIFACE_DEFAULT_MOUTH_OPEN_MAR_THRESHOLD;
    HiFaceSessionHandle session = NULL;
    REQUIRE(hiface_session_create_v1(&config, &session) == HIFACE_STATUS_OK);
    REQUIRE(session != NULL);

    float feature[HIFACE_FACE_FEATURE_DIMENSION] = {1.0f};
    float score = 0.0f;
    REQUIRE(hiface_feature_compare_v1(feature, feature, HIFACE_FACE_FEATURE_DIMENSION,
                                    &score) == HIFACE_STATUS_OK);
    REQUIRE(score == 1.0f);

    HiFaceSearchDatabaseHandle database = NULL;
    HiFaceSearchResultsHandle results = NULL;
    REQUIRE(hiface_search_open_v1(":memory:", &database) == HIFACE_STATUS_OK);
    REQUIRE(hiface_search_query_v1(database, feature, HIFACE_FACE_FEATURE_DIMENSION,
            NULL, NULL, 1, 0.8f, &results) == HIFACE_STATUS_OK);
    REQUIRE(hiface_search_results_count_v1(results) == 0);
    hiface_search_results_destroy_v1(results);
    hiface_search_close_v1(database);
    hiface_session_destroy_v1(session);
    return 0;
}
