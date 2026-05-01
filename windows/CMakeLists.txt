# Project-level configuration.
cmake_minimum_required(VERSION 3.14)
project(yuelink LANGUAGES CXX)

# The name of the executable created for the application. Change this to change
# the on-disk name of your application.
set(BINARY_NAME "yuelink")

# Explicitly opt in to modern CMake behaviors to avoid warnings with recent
# versions of CMake.
cmake_policy(VERSION 3.14...3.25)

# Define build configuration option.
get_property(IS_MULTICONFIG GLOBAL PROPERTY GENERATOR_IS_MULTI_CONFIG)
if(IS_MULTICONFIG)
  set(CMAKE_CONFIGURATION_TYPES "Debug;Profile;Release"
    CACHE STRING "" FORCE)
else()
  if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE "Debug" CACHE
      STRING "Flutter build mode" FORCE)
    set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS
      "Debug" "Profile" "Release")
  endif()
endif()
# Define settings for the Profile build mode.
set(CMAKE_EXE_LINKER_FLAGS_PROFILE "${CMAKE_EXE_LINKER_FLAGS_RELEASE}")
set(CMAKE_SHARED_LINKER_FLAGS_PROFILE "${CMAKE_SHARED_LINKER_FLAGS_RELEASE}")
set(CMAKE_C_FLAGS_PROFILE "${CMAKE_C_FLAGS_RELEASE}")
set(CMAKE_CXX_FLAGS_PROFILE "${CMAKE_CXX_FLAGS_RELEASE}")

# Use Unicode for all projects.
add_definitions(-DUNICODE -D_UNICODE)

# Compilation settings that should be applied to most targets.
#
# Be cautious about adding new options here, as plugins use this function by
# default. In most cases, you should add new options to specific targets instead
# of modifying this function.
function(APPLY_STANDARD_SETTINGS TARGET)
  target_compile_features(${TARGET} PUBLIC cxx_std_17)
  target_compile_options(${TARGET} PRIVATE /W4 /WX /wd"4100")
  target_compile_options(${TARGET} PRIVATE /EHsc)
  target_compile_definitions(${TARGET} PRIVATE "_HAS_EXCEPTIONS=0")
  target_compile_definitions(${TARGET} PRIVATE "$<$<CONFIG:Debug>:_DEBUG>")
endfunction()

# Flutter library and tool build rules.
set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")
add_subdirectory(${FLUTTER_MANAGED_DIR})

# Application build; see runner/CMakeLists.txt.
add_subdirectory("runner")


# Generated plugin build rules, which manage building the plugins and adding
# them to the application.
include(flutter/generated_plugins.cmake)


# === Installation ===
# Support files are copied into place next to the executable, so that it can
# run in place. This is done instead of making a separate bundle (as on Linux)
# so that building and running from within Visual Studio will work.
set(BUILD_BUNDLE_DIR "$<TARGET_FILE_DIR:${BINARY_NAME}>")
# Make the "install" step default, as it's required to run.
set(CMAKE_VS_INCLUDE_INSTALL_TO_DEFAULT_BUILD 1)
if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
  set(CMAKE_INSTALL_PREFIX "${BUILD_BUNDLE_DIR}" CACHE PATH "..." FORCE)
endif()

set(INSTALL_BUNDLE_DATA_DIR "${CMAKE_INSTALL_PREFIX}/data")
set(INSTALL_BUNDLE_LIB_DIR "${CMAKE_INSTALL_PREFIX}")

install(TARGETS ${BINARY_NAME} RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_ICU_DATA_FILE}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

if(PLUGIN_BUNDLED_LIBRARIES)
  install(FILES "${PLUGIN_BUNDLED_LIBRARIES}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endif()

# Copy the native assets provided by the build.dart from all packages.
set(NATIVE_ASSETS_DIR "${PROJECT_BUILD_DIR}native_assets/windows/")
install(DIRECTORY "${NATIVE_ASSETS_DIR}"
   DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
   COMPONENT Runtime)

# Fully re-copy the assets directory on each build to avoid having stale files
# from a previous install.
set(FLUTTER_ASSET_DIR_NAME "flutter_assets")
install(CODE "
  file(REMOVE_RECURSE \"${INSTALL_BUNDLE_DATA_DIR}/${FLUTTER_ASSET_DIR_NAME}\")
  " COMPONENT Runtime)
install(DIRECTORY "${PROJECT_BUILD_DIR}/${FLUTTER_ASSET_DIR_NAME}"
  DESTINATION "${INSTALL_BUNDLE_DATA_DIR}" COMPONENT Runtime)

# Install the AOT library on non-Debug builds only.
install(FILES "${AOT_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  CONFIGURATIONS Profile;Release
  COMPONENT Runtime)

# Bundle libclash.dll (Go core) next to the executable.
set(LIBCLASH_DIR "${CMAKE_CURRENT_SOURCE_DIR}/libs/amd64")
if(EXISTS "${LIBCLASH_DIR}/libclash.dll")
  install(FILES "${LIBCLASH_DIR}/libclash.dll"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endif()

if(EXISTS "${LIBCLASH_DIR}/yuelink-service-helper.exe")
  install(FILES "${LIBCLASH_DIR}/yuelink-service-helper.exe"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endif()

if(EXISTS "${LIBCLASH_DIR}/yuelink-mihomo.exe")
  install(FILES "${LIBCLASH_DIR}/yuelink-mihomo.exe"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endif()

# Wintun is required by desktop TUN on Windows. Source-of-truth lives in
# windows/third_party/wintun/<arch>/wintun.dll, fetched + sha256-pinned by
# scripts/check_windows_wintun_bundle.ps1 (run by CI before flutter build).
# Falls back to the legacy libs/amd64 path so existing dev machines keep working.
#
# Build-time is intentionally non-fatal — running flutter build on a host that
# never set up Wintun is fine; the runtime diagnostic in
# lib/core/tun/desktop_tun_diagnostics.dart surfaces error_class=missing_driver
# and the UI says "Wintun 驱动缺失". The release-gate (post-build
# check_windows_wintun_bundle.ps1 -Verify) is what blocks shipping a Windows
# installer without the DLL.
set(WINTUN_THIRD_PARTY_DIR "${CMAKE_CURRENT_SOURCE_DIR}/third_party/wintun")
if(CMAKE_GENERATOR_PLATFORM STREQUAL "ARM64" OR CMAKE_VS_PLATFORM_NAME STREQUAL "ARM64")
  set(WINTUN_ARCH "arm64")
else()
  set(WINTUN_ARCH "amd64")
endif()
set(WINTUN_DLL_THIRD_PARTY "${WINTUN_THIRD_PARTY_DIR}/${WINTUN_ARCH}/wintun.dll")
set(WINTUN_DLL_LEGACY      "${LIBCLASH_DIR}/wintun.dll")
if(EXISTS "${WINTUN_DLL_THIRD_PARTY}")
  install(FILES "${WINTUN_DLL_THIRD_PARTY}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
elseif(EXISTS "${WINTUN_DLL_LEGACY}")
  install(FILES "${WINTUN_DLL_LEGACY}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
else()
  message(WARNING
    "wintun.dll not found at ${WINTUN_DLL_THIRD_PARTY} or ${WINTUN_DLL_LEGACY}. "
    "Run `pwsh scripts/check_windows_wintun_bundle.ps1 -Download` before packaging "
    "a release; without it desktop TUN will fail with error_class=missing_driver."
  )
endif()
