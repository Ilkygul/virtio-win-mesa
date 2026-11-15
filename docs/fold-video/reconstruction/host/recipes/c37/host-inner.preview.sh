set -eo pipefail
cd /work/crosvm_build
source build/envsetup.sh
lunch aosp_arm64 trunk_staging eng
sha256sum -c /codex-virgl-inputs.sha256
NINJA_ARGS="-k 0" ALLOW_MISSING_DEPENDENCIES=true TARGET_BUILD_UNBUNDLED=true m out/soong/.intermediates/external/virglrenderer/libvirglrenderer/android_arm64_armv8-a_shared/libvirglrenderer.so out/soong/.intermediates/external/virglrenderer/virgl_render_server/android_arm64_armv8-a/virgl_render_server -j8
