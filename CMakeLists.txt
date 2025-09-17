cmake_minimum_required(VERSION 3.10)
project(MicroPanel VERSION 2.0.0 LANGUAGES C CXX)

# Set C++ standard
set(CMAKE_CXX_STANDARD 14)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# Add compiler warnings and optimizations
if(CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang")
    add_compile_options(-Wall -Wextra -Wpedantic -Os -ffunction-sections -fdata-sections)
    add_link_options(-Wl,--gc-sections)
endif()

# Find required packages with better error handling
find_package(Threads REQUIRED)

# Find udev library
find_library(UDEV_LIBRARY udev REQUIRED)
if(NOT UDEV_LIBRARY)
    message(FATAL_ERROR "libudev not found! Install with: sudo apt-get install libudev-dev")
endif()

# Find I2C library with proper error handling
find_library(I2C_LIBRARY i2c)
if(NOT I2C_LIBRARY)
    message(FATAL_ERROR "libi2c not found! Install with: sudo apt-get install libi2c-dev i2c-tools")
endif()

# Check for i2c headers
find_path(I2C_INCLUDE_DIR 
    NAMES i2c/smbus.h
    PATHS /usr/include /usr/local/include
)
if(NOT I2C_INCLUDE_DIR)
    message(FATAL_ERROR "i2c/smbus.h not found! Install with: sudo apt-get install libi2c-dev")
endif()

# Find libcurl for SpeedTestScreen
find_package(CURL REQUIRED)
if(NOT CURL_FOUND)
    message(FATAL_ERROR "libcurl not found! Install with: sudo apt-get install libcurl4-openssl-dev")
endif()

# Find nlohmann/json
find_package(nlohmann_json 3.7.3 QUIET)
if(nlohmann_json_FOUND)
    message(STATUS "Using system-installed nlohmann/json")
else()
    message(FATAL_ERROR "nlohmann/json not found! Install with: sudo apt-get install nlohmann-json3-dev")
endif()

# Include directories
include_directories(
    ${CMAKE_CURRENT_SOURCE_DIR}/include
    ${CURL_INCLUDE_DIRS}
    ${I2C_INCLUDE_DIR}
)

# Define source files by directory
set(SOURCES_PERSISTENCE
    src/PersistentStorage.cpp
    src/ModuleDependency.cpp
)

set(SOURCES_DEVICES
    src/devices/DisplayDevice.cpp
    src/devices/I2CDisplayDevice.cpp
    src/devices/Font8x8.cpp
    src/devices/InputDevice.cpp
    src/devices/DeviceManager.cpp
    src/devices/MultiInputDevice.cpp
)

set(SOURCES_MENU
    src/menu/Display.cpp
    src/menu/Menu.cpp
)

set(SOURCES_MODULES
    src/modules/ScreenModule.cpp
    src/modules/SystemStatsScreen.cpp
    src/modules/NetworkInfoScreen.cpp
    src/modules/NetSettingsScreen.cpp
    src/modules/NetInfoScreen.cpp
    src/modules/BrightnessScreen.cpp
    src/modules/InternetTestScreen.cpp
    src/modules/WiFiSettingsScreen.cpp
    src/modules/HelloCounterScreens.cpp
    src/modules/IPSelector.cpp
    src/modules/IPSelectorScreen.cpp
    src/modules/IPPingScreen.cpp
    src/modules/MenuScreenModule.cpp
    src/modules/SpeedTestScreen.cpp
    src/modules/ThroughputServerScreen.cpp
    src/modules/ThroughputClientScreen.cpp
    src/modules/GenericListScreen.cpp
)

set(SOURCES_MAIN
    src/Logger.cpp
    src/MicroPanel.cpp
)

# Combine all sources
set(SOURCES
    ${SOURCES_DEVICES}
    ${SOURCES_MENU}
    ${SOURCES_MODULES}
    ${SOURCES_PERSISTENCE}
    ${SOURCES_MAIN}
)

# Define executable
add_executable(micropanel ${SOURCES})

# Compile patch-generator utility
add_executable(patch-generator utils/patch-generator.c)

# Link libraries in proper order
target_link_libraries(micropanel
    PRIVATE
    Threads::Threads
    ${UDEV_LIBRARY}
    ${CURL_LIBRARIES}
    ${I2C_LIBRARY}
    nlohmann_json::nlohmann_json
)

# Configuration options
option(INSTALL_ALL_CONFIGS "Install all configuration files" OFF)
set(INSTALL_SCREEN "" CACHE STRING "Specific screen config to install (e.g., config-pios.json)")
option(INSTALL_SYSTEMD_SERVICE "Install systemd service file" OFF)
option(INSTALL_HELPER_SCRIPTS "Install helper shell scripts" OFF)
option(INSTALL_MEDIA_FILES "Install media files to share/micropanel/media" OFF)
set(SERVICE_USER "root" CACHE STRING "User to run micropanel service as")

# Install target
install(TARGETS micropanel patch-generator
    RUNTIME DESTINATION bin
)

# Install init.d script for SysV init systems (only if systemd service is not installed)
if(NOT INSTALL_SYSTEMD_SERVICE)
    install(FILES scripts/S99Micropanel
        DESTINATION etc/init.d
        PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE GROUP_READ GROUP_EXECUTE WORLD_READ WORLD_EXECUTE
    )
    message(STATUS "Will install SysV init script to etc/init.d/micropanel")
endif()

# Install helper shell scripts
if(INSTALL_HELPER_SCRIPTS)
    install(FILES
        scripts/dhcp-net-settings.sh
        scripts/list-images.sh
        scripts/pi-config-txt.sh
        scripts/play-video.sh
        scripts/stop-video.sh
        scripts/buzzer.sh
        scripts/dhcp-net-settings-pios.sh
        scripts/hdmi-patch.sh
        scripts/list-videos.sh
        scripts/play-image.sh
        scripts/stop-image.sh
        DESTINATION bin
        PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE GROUP_READ GROUP_EXECUTE WORLD_READ WORLD_EXECUTE
    )
    message(STATUS "Will install helper scripts to bin/")
endif()

# Install media files
if(INSTALL_MEDIA_FILES)
    if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/media")
        install(DIRECTORY media/
            DESTINATION share/micropanel/media
            FILES_MATCHING PATTERN "*"
        )
        message(STATUS "Will install media files to share/micropanel/media/")
    else()
        message(WARNING "Media directory not found at ${CMAKE_CURRENT_SOURCE_DIR}/media")
    endif()
endif()

# Install configuration files
if(INSTALL_ALL_CONFIGS)
    # Install all configuration files from screens directory
    install(DIRECTORY screens/
        DESTINATION etc/micropanel/screens
        FILES_MATCHING PATTERN "*.json"
        PATTERN "*.sh" EXCLUDE
    )
    message(STATUS "Will install all configuration files to etc/micropanel/screens/")
elseif(INSTALL_SCREEN)
    # Install specific configuration file
    if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/screens/${INSTALL_SCREEN}")
        install(FILES "screens/${INSTALL_SCREEN}"
            DESTINATION etc/micropanel
            RENAME config.json
        )
        message(STATUS "Will install ${INSTALL_SCREEN} as etc/micropanel/config.json")
    else()
        message(FATAL_ERROR "Configuration file screens/${INSTALL_SCREEN} not found!")
    endif()
else()
    # Default: install screens.json as config.json if it exists
    if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/screens/screens.json")
        install(FILES "screens/screens.json"
            DESTINATION etc/micropanel
            RENAME config.json
        )
        message(STATUS "Will install screens.json as etc/micropanel/config.json (default)")
    elseif(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/screens/micropanel-config.json")
        install(FILES "screens/micropanel-config.json"
            DESTINATION etc/micropanel
            RENAME config.json
        )
        message(STATUS "Will install micropanel-config.json as etc/micropanel/config.json (fallback)")
    else()
        message(WARNING "No default configuration file found in screens/ directory")
    endif()
endif()

# Install additional resources if they exist (optional)
option(INSTALL_ADDITIONAL_CONFIGS "Install configs/ directory" OFF)
if(INSTALL_ADDITIONAL_CONFIGS AND EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/configs")
    install(DIRECTORY configs/
        DESTINATION etc/micropanel/configs
        FILES_MATCHING PATTERN "*"
    )
    message(STATUS "Will install configs/ directory to etc/micropanel/configs/")
endif()

# Configure and install systemd service file
if(INSTALL_SYSTEMD_SERVICE)
    # Configure the service file with proper paths
    configure_file(
        ${CMAKE_CURRENT_SOURCE_DIR}/micropanel.service.in
        ${CMAKE_CURRENT_BINARY_DIR}/micropanel.service
        @ONLY
    )
    
    install(FILES ${CMAKE_CURRENT_BINARY_DIR}/micropanel.service
        DESTINATION lib/systemd/system
    )
    message(STATUS "Will install systemd service file")
    message(STATUS "  Service will run as: ${SERVICE_USER}")
    message(STATUS "  Binary path: ${CMAKE_INSTALL_PREFIX}/bin/micropanel")
    message(STATUS "  Config path: ${CMAKE_INSTALL_PREFIX}/etc/micropanel/config.json")
endif()

# Strip the binary to reduce size (only in Release mode)
if(CMAKE_BUILD_TYPE STREQUAL "Release")
    add_custom_command(TARGET micropanel POST_BUILD
        COMMAND ${CMAKE_STRIP} $<TARGET_FILE:micropanel>
        COMMENT "Stripping binary for reduced size"
    )
endif()

# Print configuration summary
message(STATUS "MicroPanel Configuration Summary:")
message(STATUS "  Build type: ${CMAKE_BUILD_TYPE}")
message(STATUS "  C++ standard: ${CMAKE_CXX_STANDARD}")
message(STATUS "  I2C library: ${I2C_LIBRARY}")
message(STATUS "  UDEV library: ${UDEV_LIBRARY}")
message(STATUS "  CURL libraries: ${CURL_LIBRARIES}")

# Add uninstall target
configure_file(
    "${CMAKE_CURRENT_SOURCE_DIR}/cmake/cmake_uninstall.cmake.in"
    "${CMAKE_CURRENT_BINARY_DIR}/cmake_uninstall.cmake"
    @ONLY
)
add_custom_target(uninstall
    COMMAND ${CMAKE_COMMAND} -P ${CMAKE_CURRENT_BINARY_DIR}/cmake_uninstall.cmake
)