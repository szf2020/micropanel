# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

µPanel (micropanel) is a C++ daemon that provides a USB-based Human-Machine Interface for embedded Linux devices using an RP2040-based USB HID display dongle with OLED screen, rotary encoder, buttons, and buzzer.

**Hardware Components:**
- SSD1306 128x64 OLED display
- Rotary encoder with push button
- Optional directional push buttons (up/down/left/right/enter)
- Buzzer for audible feedback
- Optional sensors (temperature/humidity/gas)

**Target Use Cases:**
- IT and AV professionals finding IP addresses of newly deployed devices in large networks
- Network administrators diagnosing Ethernet port issues without heavy gear
- Embedded developers needing minimal local displays for headless devices

## Architecture

The codebase follows a modular architecture with clear separation of concerns:

### Core Components
- **MicroPanel**: Main application class that orchestrates the system (`src/MicroPanel.cpp`)
- **DeviceManager**: Handles USB device detection and communication (`src/devices/DeviceManager.cpp`)
- **DisplayDevice/I2CDisplayDevice**: Abstracts display communication (`src/devices/`)
- **InputDevice/MultiInputDevice**: Handles input events from rotary encoder and buttons (`src/devices/`)
- **MenuSystem**: Core menu navigation logic (`src/menu/`)
- **ScreenModules**: Individual screen implementations for different functionality (`src/modules/`)

### Key Directories
- `src/devices/`: Hardware abstraction layer for display and input devices
- `src/menu/`: Menu system and display rendering
- `src/modules/`: Screen modules (network info, system stats, speed tests, etc.)
- `include/`: Header files with interface definitions
- `screens/`: JSON configuration files for different deployment types
- `scripts/`: Shell scripts for system operations (networking, media playback)
- `configs/`: System configuration files

### Configuration System
- JSON-based configuration in `screens/` directory
- Type-specific configs: `config-debian.json`, `config-pios.json`
- Additional variants: `config-debian-iperf.json`, `config-pios-iperf.json`
- Example configs: `screens.json`, `screens-minimal.json`, `screens-all.json`, `nested-screens.json`
- Modular screen system with dependency management
- Runtime path adjustment via `screens/update-config-path.sh`

### Device Communication
- **Serial Protocol**: Commands sent to `/dev/ttyACM0` for display control (clear, text, brightness, buzzer)
- **Input Events**: Received from `/dev/input/eventX` for rotary encoder and button presses
- **I2C Support**: Direct I2C communication for Raspberry Pi deployments (`/dev/i2c-1`, `/dev/i2c-3`)
- **GPIO Mode**: Alternative input handling using GPIO buttons for Raspberry Pi (`-i gpio`)
- **Auto-Detection**: Automatic USB device detection and reconnection (enabled by default)

### Serial Command Protocol
Core display commands sent to `/dev/ttyACM0`:
- `0x01`: Clear display
- `0x02 [X] [Y] Text`: Display text at position
- `0x03 [X] [Y]`: Set cursor position
- `0x04 [0/1]`: Invert display ON/OFF
- `0x05 [0-255]`: Set brightness
- `0x06`: Draw progress bar
- `0x07 [0/1]`: Display OFF/ON
- `0x08 [0/1] [Hz]`: Buzzer control

## Build System

**Build Commands:**
```bash
# Clean build
rm -rf build && mkdir build && cd build

# Configure and build
cmake ..
make -j$(nproc)

# Binary location: build/micropanel
```

**Dependencies:**
- `libi2c-dev`, `i2c-tools` (I2C communication)
- `cmake`, `libudev-dev` (build system and USB device detection)
- `nlohmann-json3-dev` (JSON configuration parsing)
- `libcurl4-openssl-dev` (HTTP requests for speed tests)
- `iperf3` (network throughput testing)

**Compiler Requirements:**
- C++14 standard or higher
- GCC or Clang with warnings enabled (-Wall -Wextra -Wpedantic)
- Link-time optimization and binary stripping for minimal size

**Installation:**
```bash
# Full system setup (requires root)
sudo ./setup.sh -t debian  # For Debian/Ubuntu systems
sudo ./setup.sh -t pios    # For Raspberry Pi OS

# Manual installation with configuration options
sudo make install  # Installs to /usr/local/bin

# Advanced installation with specific config
cmake -DINSTALL_SCREEN=config-pios.json -DINSTALL_SYSTEMD_SERVICE=ON ..
make && sudo make install

# Installation with systemd service and custom arguments
cmake -DINSTALL_SYSTEMD_SERVICE=ON -DSYSTEMD_UNITFILE_ARGS="-i gpio -s /dev/i2c-3" ..
make && sudo make install

# Install all configuration files
cmake -DINSTALL_ALL_CONFIGS=ON ..
make && sudo make install
```

**Build Configuration Options:**
- `INSTALL_ALL_CONFIGS=ON`: Install all JSON config files to `/etc/micropanel/screens/`
- `INSTALL_SCREEN=config-name.json`: Install specific config as `/etc/micropanel/config.json`
- `INSTALL_SYSTEMD_SERVICE=ON`: Install systemd service file
- `SERVICE_USER=username`: Set service user (default: root)
- `SYSTEMD_UNITFILE_ARGS="args"`: Additional command line arguments for micropanel in systemd service
- `INSTALL_ADDITIONAL_CONFIGS=ON`: Install configs/ directory if present

## Development Workflow

**Testing the Build:**
- No automated test suite - testing is done with actual hardware
- Use verbose mode: `./build/micropanel -v -c screens/config-debian.json`
- Test GPIO mode (Pi): `./build/micropanel -i gpio -s /dev/i2c-1 -c screens/config-pios.json -v`
- Test auto-detection: `./build/micropanel -a -c screens/config-debian.json -v`
- Check systemd service: `systemctl status micropanel`
- Monitor logs: `tail -f /tmp/micropanel.log`

**Common Development Tasks:**
- Modify screen modules in `src/modules/` for new functionality
- Update JSON configs in `screens/` for menu changes
- Add new device support in `src/devices/`
- Extend input handling in `MultiInputDevice.cpp`

**Adding GPIO Support to Screen Modules:**
When creating new interactive screen modules that need GPIO input support:
1. Add `handleGPIORotation(int direction)` and `handleGPIOButtonPress()` methods to the class header
2. Implement both methods in the .cpp file following existing patterns
3. Add module support to `MicroPanel::simulateRotationForModule()` in `src/MicroPanel.cpp`
4. Add module support to the button press handling section in `MicroPanel::runModuleWithGPIOInput()`
5. For PIMPL-based modules (like NetSettingsScreen), add corresponding methods to the Impl class and delegate from public methods
6. Ensure proper exit handling: GPIO button methods should return `false` when the module should exit (check `m_shouldExit` flags)
7. Examples: `NetInfoScreen`, `IPPingScreen`, `ThroughputServerScreen`, `ThroughputClientScreen`, `NetSettingsScreen`, `WiFiSettingsScreen`

## Recent Development History

### GPIO Support Expansion (Latest)
- **NetSettingsScreen & WiFiSettingsScreen GPIO Support**: Added complete GPIO input support for network configuration screens
- **Complex Menu Navigation**: Implemented multi-level GPIO navigation for NetSettingsScreen (main menu, mode selection, IP address editing)
- **IP Selector Integration**: GPIO input now works seamlessly with IP address editing fields in network settings
- **MicroPanel Integration**: Added proper module type detection and GPIO handling in `MicroPanel::runModuleWithGPIOInput()`
- **Exit Mechanism Fix**: Fixed "Back" button functionality in NetSettingsScreen GPIO mode by properly handling `m_shouldExit` flag
- **Bounded Navigation**: Applied consistent non-wraparound navigation patterns across all newly supported modules

### Navigation System Improvements
- **Eliminated Page Refresh Flicker**: Fixed ThroughputClientScreen page refresh issue when navigating up from end of list by replacing pagination with smooth scrolling
- **Consistent Navigation Behavior**: Changed from wraparound navigation to bounded navigation (stops at first/last item) to match GenericListScreen pattern
- **Anti-Flicker Improvements**: Enhanced all screen modules with proper text padding (16 characters) and minimal update rendering
- **ThroughputServerScreen Optimization**: Added `renderOptions(bool fullRedraw)` overload for selective updates instead of full screen clears
- **Scroll Indicator Optimization**: Only draw scroll indicators on full redraws to reduce unnecessary screen updates in submenu rendering

### Previous GPIO Support Implementation
- **ThroughputServerScreen & ThroughputClientScreen**: Added full GPIO support with `handleGPIORotation()` and `handleGPIOButtonPress()` methods
- **IP Address Picker Fix**: Fixed custom IP selection in ThroughputClientScreen by adding missing `m_ipSelector->handleButton()` call to activate cursor mode
- **Navigation Arrow Fix**: Fixed Server IP submenu navigation using proper direction checking instead of problematic modulo math
- **Main Menu Navigation**: Fixed GPIO mode "Main Menu" vs "Back" behavior by adding missing flag propagation logic in `MenuScreenModule::handleGPIOButtonPress()`

### Performance & UI Consistency
- **GenericListScreen Pattern**: All screen modules now follow consistent navigation patterns with minimal updates and proper text padding
- **Smooth Scrolling**: Replaced pagination-based navigation with smooth scrolling for better user experience
- **Reduced Display Commands**: Optimized rendering to minimize display command frequency and reduce flicker

### Busybox Compatibility Improvements
- **IPPingScreen Busybox Fix**: Fixed ping functionality for minimal Linux environments by replacing GNU-specific `grep -oP` with POSIX-compatible `awk` command pipeline
- **Cross-Platform Ping**: Updated ping time extraction from `grep -oP 'time=\\K[0-9.]+'` to `grep 'time=' | awk -F'time=' '{print $2}' | awk '{print $1}'`
- **Enhanced Portability**: Ping functionality now works on busybox, standard Linux, Ubuntu, Raspberry Pi OS, and other Unix-like systems

### Script Optimization & Template System
- **pi-config-txt.sh Optimization**: Reduced script from 807 lines to ~400 lines (50% reduction) by eliminating 400+ lines of configuration duplication
- **Template-Based Architecture**: Introduced external template system using `config-base.txt.in` and `display-configs.conf` for maintainable display configurations
- **Data-Driven Approach**: All display types now defined in single configuration file (`display-configs.conf`) with format: `TYPE:RESOLUTION:HDMI_TIMINGS:PIXEL_FREQ:FB_WIDTH:FB_HEIGHT:DESCRIPTION`
- **Easy Maintenance**: Adding new display types requires only one line addition to configuration file, no code changes needed
- **Consistent Output**: All configurations use shared base template ensuring consistency across display types

### Current Status & Capabilities
- **Complete GPIO Support**: All interactive screen modules now support GPIO input mode (`-i gpio`)
- **Comprehensive Navigation**: Bounded navigation with anti-flicker rendering across all modules
- **Network Configuration**: Full GPIO support for IP settings, WiFi settings, and throughput testing
- **Busybox Compatible**: All network tools work on minimal Linux environments with busybox utilities
- **Production Ready**: Stable GPIO integration with proper exit handling and state management
- **Main Menu Navigation**: ScreenCallback pattern enables "Main Menu" functionality in deeply nested screens

### Adding "Main Menu" to Nested Screen Modules

**Problem**: Deep menu navigation (e.g., Main→Network→Status→Interfaces) requires multiple "Back" presses to reach main menu.

**Solution**: Use the proven ScreenCallback pattern that leverages existing MenuScreenModule infrastructure.

#### Implementation Pattern (4 Steps):

**Step 1: Add ScreenCallback Support to Target Module**
```cpp
// In include/ScreenModules.h - Add to class declaration:
class YourScreen : public ScreenModule {
public:
    // ... existing methods ...

    // Callback support (same pattern as GenericListScreen)
    void setCallback(ScreenCallback* callback) { m_callback = callback; }
    void notifyCallback(const std::string& action, const std::string& value);

private:
    ScreenCallback* m_callback = nullptr;
};

// In src/modules/YourScreen.cpp - Implement the method:
void YourScreen::notifyCallback(const std::string& action, const std::string& value) {
    if (m_callback) {
        m_callback->onScreenAction(getModuleId(), action, value);
    }
}
```

**Step 2: Update MenuScreenModule Integration**
```cpp
// In src/modules/MenuScreenModule.cpp - Add to executeSubmenuAction():
// If this is a YourScreen, set its callback to this
auto yourScreen = std::dynamic_pointer_cast<YourScreen>(module);
if (yourScreen) {
    yourScreen->setCallback(this);
}
```

**Step 3: Handle Exit to Main Menu Action**
```cpp
// In src/modules/MenuScreenModule.cpp - Add to onScreenAction():
} else if (action == "exit_to_main_menu") {
    // Handle request to navigate to main menu from child screen
    Logger::debug("Child screen requested exit to main menu: " + screenId);
    navigateToMainMenu();  // Uses existing proven mechanism
}
```

**Step 4: Add Main Menu Option to Target Screen**
```cpp
// Add "Main Menu" as menu option (after "Back")
// When selected, trigger callback:
notifyCallback("exit_to_main_menu", "");
```

#### Complete Working Example (NetInfoScreen):

**Header Addition** (`include/ScreenModules.h`):
```cpp
class NetInfoScreen : public ScreenModule {
    // Callback support
    void setCallback(ScreenCallback* callback) { m_callback = callback; }
    void notifyCallback(const std::string& action, const std::string& value);
private:
    ScreenCallback* m_callback = nullptr;
};
```

**Implementation** (`src/modules/NetInfoScreen.cpp`):
```cpp
// Add menu options during interface list building:
InterfaceInfo backOption;
backOption.name = "Back";
backOption.linkUp = false;  // Prevent asterisk indicators on menu items
m_interfaces.push_back(backOption);

InterfaceInfo mainMenuOption;
mainMenuOption.name = "Main Menu";
mainMenuOption.linkUp = false;
m_interfaces.push_back(mainMenuOption);

// Handle selection in button press logic:
if (selectedIndex == interfaces.size() - 1) {
    // "Main Menu" selected
    notifyCallback("exit_to_main_menu", "");
    shouldExit = true;
} else if (selectedIndex == interfaces.size() - 2) {
    // "Back" selected
    shouldExit = true;
}
```

#### Key Design Principles:

1. **Leverage Existing Infrastructure**: Uses MenuScreenModule's proven `navigateToMainMenu()` mechanism
2. **ScreenCallback Pattern**: Same communication pattern as GenericListScreen uses successfully
3. **Defensive Programming**: Always initialize `linkUp = false` for menu items to prevent visual artifacts
4. **Proper Indexing**: Account for multiple menu items (`size() - 2` for last interface, `size() - 1` for Main Menu)
5. **Selection Preservation**: Handle all items during refresh cycles to prevent index confusion

#### Benefits:
- **Reusable**: Works for any ScreenModule (NetInfoScreen, IPPingScreen, etc.)
- **Proven**: Uses existing, tested MenuScreenModule navigation logic
- **Consistent**: Matches existing "Main Menu" behavior in other menu levels
- **Reliable**: Handles edge cases like periodic refresh and selection preservation

### Known Issues & Limitations
- **Hardware Dependency**: Requires actual µPanel hardware for full testing
- **Display Command Delays**: Navigation has slight delays due to required 10ms delays between display commands

**Service Management:**
```bash
# Control systemd service
sudo systemctl start/stop/restart micropanel
sudo systemctl enable/disable micropanel
journalctl -u micropanel -f  # Follow service logs
```

**Hardware Debugging:**
```bash
# Check USB device detection
lsusb | grep -i hid
ls /dev/ttyACM*
ls /dev/input/event*

# Test I2C (Raspberry Pi)
i2cdetect -y 1
i2cdetect -y 3

# Check GPIO buttons (Raspberry Pi)
dmesg | grep button
cat /proc/bus/input/devices | grep -A5 "gpio-keys"
```

## Code Patterns

- **RAII**: Proper resource management for device handles
- **Factory Pattern**: Screen module creation via ScreenModuleFactory
- **Observer Pattern**: Input event handling and menu navigation
- **Dependency Injection**: Module dependencies managed via ModuleDependency.cpp
- **State Machine**: Menu navigation and screen transitions
- **GPIO Support Pattern**: Interactive screen modules implement `handleGPIORotation(int direction)` and `handleGPIOButtonPress()` methods for GPIO input compatibility

### Navigation & Rendering Patterns
**Anti-Flicker Rendering** (follow GenericListScreen pattern):
- Use `render*Method(bool fullRedraw)` overloads for all submenu methods
- Clear only selection markers on minimal updates: `m_display->drawText(0, yPos, " ")`
- Pad all text to 16 characters: `while (text.length() < 16) text += " ";`
- Draw scroll indicators only on `fullRedraw=true` to reduce flicker

**Bounded Navigation** (stops at first/last item, no wraparound):
```cpp
if (direction < 0) {
    if (currentIndex > 0) currentIndex--;
} else {
    if (currentIndex < maxIndex) currentIndex++;
}
```

**Smooth Scrolling** for long lists:
```cpp
if (selectedIndex < firstVisibleItem) {
    firstVisibleItem = selectedIndex;
} else if (selectedIndex >= firstVisibleItem + MAX_VISIBLE_ITEMS) {
    firstVisibleItem = selectedIndex - MAX_VISIBLE_ITEMS + 1;
}
```

## Important Notes

- **Hardware Dependent**: Requires actual µPanel hardware for full testing
- **Root Privileges**: Many operations require root access for device communication
- **Platform Specific**: Different configurations for Debian vs Raspberry Pi OS
- **Real-time Constraints**: Input processing and display updates must be responsive
- **Serial Communication**: Binary protocol implementation in DisplayDevice classes
- **Dual Input Modes**: Traditional USB HID vs GPIO button input for different hardware configurations
- **Auto-Detection**: Default behavior waits for device connection and handles reconnection
- **Mixed Device Types**: Supports both USB serial and I2C displays simultaneously
- **GPIO Input Integration**: Screen modules handle GPIO input via dedicated methods rather than traditional input polling

## Command Line Options

**Key Arguments:**
```bash
./micropanel [OPTIONS]
  -i DEVICE   Input device (/dev/input/eventX or "gpio" for Pi GPIO buttons)
  -s DEVICE   Display device (/dev/ttyACM0 or /dev/i2c-1 for I2C)
  -c FILE     JSON configuration file (screens/config-*.json)
  -a          Enable auto-detection (default: enabled)
  -v          Verbose debug output
  -p          Power save mode (display timeout)
```

**Configuration Examples:**
```bash
# Raspberry Pi with GPIO and I2C display
./micropanel -i gpio -s /dev/i2c-1 -c screens/config-pios.json

# Standard USB setup with auto-detection
./micropanel -c screens/config-debian.json

# Manual device specification
./micropanel -i /dev/input/event11 -s /dev/ttyACM0 -c screens/config-debian.json
```