#include "MultiInputDevice.h"
#include "Config.h"
#include <iostream>
#include <cstring>
#include <cerrno>
#include <unistd.h>
#include <fcntl.h>
#include <linux/input.h>
#include <sys/ioctl.h>
#include <dirent.h>
#include <fstream>
#include <algorithm>

MultiInputDevice::MultiInputDevice() : DeviceInterface("multi-gpio") {
    // Auto-detect GPIO button devices on construction
    auto devicePaths = detectGPIOButtonDevices();
    
    std::cout << "MultiInputDevice: Auto-detected " << devicePaths.size() << " GPIO button devices" << std::endl;
    
    for (const auto& path : devicePaths) {
        addDevice(path);
    }
}

MultiInputDevice::~MultiInputDevice() {
    close();
}

std::vector<std::string> MultiInputDevice::detectGPIOButtonDevices() {
    std::vector<std::string> devices;
    
    // Scan /dev/input/event* for GPIO button devices
    DIR* dir = opendir("/dev/input");
    if (!dir) {
        std::cerr << "Failed to open /dev/input directory" << std::endl;
        return devices;
    }
    
    struct dirent* entry;
    while ((entry = readdir(dir)) != nullptr) {
        if (strncmp(entry->d_name, "event", 5) != 0) {
            continue;
        }
        
        std::string devicePath = "/dev/input/";
        devicePath += entry->d_name;
        
        // Check if this is a GPIO button device
        int fd = ::open(devicePath.c_str(), O_RDONLY | O_NONBLOCK);
        if (fd < 0) {
            continue;
        }
        
        // Get device name
        char name[256] = {0};
        if (ioctl(fd, EVIOCGNAME(sizeof(name)), name) >= 0) {
            std::string deviceName(name);
            
            // Look for GPIO button devices (pattern: "button@X")
            if (deviceName.find("button@") == 0) {
                std::cout << "Found GPIO button device: " << devicePath << " (" << deviceName << ")" << std::endl;
                devices.push_back(devicePath);
            }
        }
        
        ::close(fd);
    }
    
    closedir(dir);
    
    // Sort devices for consistent ordering
    std::sort(devices.begin(), devices.end());
    
    return devices;
}

bool MultiInputDevice::addDevice(const std::string& devicePath) {
    m_devices.emplace_back(devicePath);
    GPIODevice& device = m_devices.back();
    
    // Get device info
    device.name = getDeviceName(devicePath);
    device.keycode = getDeviceKeycode(devicePath);
    
    std::cout << "Added GPIO device: " << devicePath 
              << " (" << device.name << ", keycode=" << device.keycode << ")" << std::endl;
    
    return true;
}

bool MultiInputDevice::open() {
    if (m_devices.empty()) {
        std::cerr << "MultiInputDevice: No GPIO devices to open" << std::endl;
        return false;
    }
    
    bool anySuccess = false;
    
    // Open all devices
    for (auto& device : m_devices) {
        if (openDevice(device)) {
            anySuccess = true;
        }
    }
    
    if (anySuccess) {
        // Set up polling file descriptors
        m_pollFds.clear();
        for (const auto& device : m_devices) {
            if (device.isOpen) {
                struct pollfd pfd;
                pfd.fd = device.fd;
                pfd.events = POLLIN;
                pfd.revents = 0;
                m_pollFds.push_back(pfd);
            }
        }
        
        logDeviceInfo();
        std::cout << "MultiInputDevice: Successfully opened " << m_pollFds.size() << " GPIO button devices" << std::endl;
    }
    
    return anySuccess;
}

void MultiInputDevice::close() {
    for (auto& device : m_devices) {
        closeDevice(device);
    }
    m_pollFds.clear();
}

bool MultiInputDevice::checkConnection() const {
    // Check if at least one device is still connected
    for (const auto& device : m_devices) {
        if (device.isOpen) {
            // Try to query the device
            char name[256];
            if (ioctl(device.fd, EVIOCGNAME(sizeof(name)), name) >= 0) {
                return true; // At least one device is working
            }
        }
    }
    return false;
}

bool MultiInputDevice::openDevice(GPIODevice& device) {
    device.fd = ::open(device.path.c_str(), O_RDONLY | O_NONBLOCK);
    if (device.fd < 0) {
        std::cerr << "Failed to open GPIO device " << device.path << ": " << strerror(errno) << std::endl;
        return false;
    }
    
    // Get exclusive access
    if (ioctl(device.fd, EVIOCGRAB, 1) < 0) {
        std::cerr << "Warning: Failed to get exclusive access to " << device.path << std::endl;
    }
    
    device.isOpen = true;
    return true;
}

void MultiInputDevice::closeDevice(GPIODevice& device) {
    if (device.isOpen && device.fd >= 0) {
        ioctl(device.fd, EVIOCGRAB, 0);
        ::close(device.fd);
        device.fd = -1;
        device.isOpen = false;
    }
}

int MultiInputDevice::getDeviceKeycode(const std::string& devicePath) {
    int fd = ::open(devicePath.c_str(), O_RDONLY);
    if (fd < 0) {
        std::cout << "DEBUG: Failed to open " << devicePath << " for keycode detection" << std::endl;
        return -1;
    }
    
    // Check which key this device supports
    unsigned long keybit[KEY_MAX/8/sizeof(long) + 1] = {0};
    if (ioctl(fd, EVIOCGBIT(EV_KEY, sizeof(keybit)), keybit) < 0) {
        std::cout << "DEBUG: Failed to get key bits for " << devicePath << std::endl;
        ::close(fd);
        return -1;
    }
    
    // Check for our specific keys
    int keycodes[] = {KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN, KEY_ENTER};
    const char* keynames[] = {"KEY_LEFT", "KEY_RIGHT", "KEY_UP", "KEY_DOWN", "KEY_ENTER"};
    
    for (int i = 0; i < 5; i++) {
        int keycode = keycodes[i];
        int byte_index = keycode / (8 * sizeof(long));
        int bit_index = keycode % (8 * sizeof(long));
        
        if (byte_index < (KEY_MAX/8/sizeof(long) + 1) && 
            (keybit[byte_index] & (1UL << bit_index))) {
            std::cout << "DEBUG: Device " << devicePath << " supports " << keynames[i] << " (" << keycode << ")" << std::endl;
            ::close(fd);
            return keycode;
        }
    }
    
    std::cout << "DEBUG: Device " << devicePath << " doesn't support any of our target keys" << std::endl;
    ::close(fd);
    return -1;
}

std::string MultiInputDevice::getDeviceName(const std::string& devicePath) {
    int fd = ::open(devicePath.c_str(), O_RDONLY);
    if (fd < 0) {
        return "unknown";
    }
    
    char name[256] = {0};
    if (ioctl(fd, EVIOCGNAME(sizeof(name)), name) >= 0) {
        ::close(fd);
        return std::string(name);
    }
    
    ::close(fd);
    return "unknown";
}

int MultiInputDevice::waitForEvents(int timeoutMs) {
    if (m_pollFds.empty()) {
        return -1;
    }
    
    // Reset revents
    for (auto& pfd : m_pollFds) {
        pfd.revents = 0;
    }
    
    // Poll all devices
    int ret = poll(m_pollFds.data(), m_pollFds.size(), timeoutMs);
    
    return ret;
}

bool MultiInputDevice::processEvents(std::function<void(int)> onRotation, std::function<void()> onButtonPress) {
    int eventsProcessed = 0;
    
    // Check each device for events
    for (size_t i = 0; i < m_devices.size(); ++i) {
        auto& device = m_devices[i];
        if (!device.isOpen) continue;
        
        // Find corresponding poll fd
        auto pollIt = std::find_if(m_pollFds.begin(), m_pollFds.end(), 
                                  [&device](const struct pollfd& pfd) { 
                                      return pfd.fd == device.fd; 
                                  });
        
        if (pollIt != m_pollFds.end() && (pollIt->revents & POLLIN)) {
            if (processDeviceEvents(device, onRotation, onButtonPress)) {
                eventsProcessed++;
            }
        }
    }
    
    return eventsProcessed > 0;
}

bool MultiInputDevice::processDeviceEvents(GPIODevice& device, std::function<void(int)> onRotation, 
                                         std::function<void()> onButtonPress) {
    struct input_event ev;
    bool eventProcessed = false;
    
    // Read all available events from this device
    while (read(device.fd, &ev, sizeof(ev)) > 0) {
        // Skip sync events
        if (ev.type == EV_SYN) continue;
        
        // Handle key events
        if (ev.type == EV_KEY && ev.value == 1) { // Key press (not release)
            std::cout << "GPIO device " << device.path << " key press: " << ev.code 
                      << " (expected: " << device.keycode << ")" << std::endl;
            
            if (ev.code == device.keycode) {
                if (ev.code == KEY_ENTER) {
                    // Handle enter button
                    if (onButtonPress) {
                        std::cout << "ENTER button pressed on " << device.path << std::endl;
                        onButtonPress();
                    }
                } else {
                    // Handle directional buttons
                    std::cout << "Direction button pressed: " << ev.code << " on " << device.path << std::endl;
                    synthesizeMovementEvent(ev.code, onRotation);
                }
                eventProcessed = true;
            }else {
                  std::cout << "DEBUG: Key mismatch - received " << ev.code << " but expected " << device.keycode << " on " << device.path << std::endl;
            }

        }
    }
    
    return eventProcessed;
}

void MultiInputDevice::synthesizeMovementEvent(int keycode, std::function<void(int)> onRotation) {
    if (!onRotation) return;
    
    int movement = 0;
    const char* direction = "";
    
    switch (keycode) {
        case KEY_LEFT:
            movement = -5;
            direction = "LEFT";
            break;
        case KEY_RIGHT:
            movement = 5;
            direction = "RIGHT";
            break;
        case KEY_UP:
            movement = -5; // UP moves menu selection up (negative Y)
            direction = "UP";
            break;
        case KEY_DOWN:
            movement = 5;  // DOWN moves menu selection down (positive Y)
            direction = "DOWN";
            break;
        default:
            return;
    }
    
    std::cout << "Synthesizing " << direction << " movement (value=" << movement << ")" << std::endl;
    onRotation(movement);
}

void MultiInputDevice::logDeviceInfo() const {
    std::cout << "=== MultiInputDevice Status ===" << std::endl;
    for (const auto& device : m_devices) {
        std::cout << "  " << device.path << " (" << device.name << "): ";
        if (device.isOpen) {
            std::cout << "OPEN, keycode=" << device.keycode;
        } else {
            std::cout << "CLOSED";
        }
        std::cout << std::endl;
    }
    std::cout << "===============================" << std::endl;
}
