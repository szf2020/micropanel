#pragma once
#include <string>
#include <vector>
#include <functional>
#include <sys/time.h>
#include <poll.h>
#include "DeviceInterfaces.h"

/**
 * Handles input from multiple GPIO button devices and rotary encoders simultaneously
 * Auto-detects and manages GPIO button devices (button@X) and rotary encoders (rotary@X)
 */
class MultiInputDevice : public DeviceInterface {
public:
    MultiInputDevice();
    ~MultiInputDevice();
    bool open() override;
    void close() override;
    bool checkConnection() const override;
    // Input processing (same interface as InputDevice)
    bool processEvents(std::function<void(int)> onRotation, std::function<void()> onButtonPress);
    int waitForEvents(int timeoutMs);
    // Auto-detection and device management
    static std::vector<std::string> detectGPIOButtonDevices();
    bool addDevice(const std::string& devicePath);
    size_t getDeviceCount() const { return m_devices.size(); }

private:
    enum class DeviceType {
        BUTTON,
        ROTARY_ENCODER
    };

    struct GPIODevice {
        std::string path;
        int fd;
        std::string name;
        int keycode;        // For button devices
        DeviceType type;    // NEW: Device type
        int lastRotaryValue; // NEW: For rotary encoder state tracking
        bool isOpen;
        
        GPIODevice(const std::string& p) : path(p), fd(-1), keycode(-1), 
                                          type(DeviceType::BUTTON), lastRotaryValue(0), isOpen(false) {}
    };

    std::vector<GPIODevice> m_devices;
    std::vector<struct pollfd> m_pollFds;

    // Device management
    bool openDevice(GPIODevice& device);
    void closeDevice(GPIODevice& device);
    int getDeviceKeycode(const std::string& devicePath);
    std::string getDeviceName(const std::string& devicePath);
    DeviceType detectDeviceType(const std::string& devicePath); // NEW: Device type detection

    // Event processing helpers
    bool processDeviceEvents(GPIODevice& device, std::function<void(int)> onRotation,
                           std::function<void()> onButtonPress);
    void synthesizeMovementEvent(int keycode, std::function<void(int)> onRotation);
    void processRotaryEncoderEvent(GPIODevice& device, int relativeValue, std::function<void(int)> onRotation); // NEW

    // Debug/logging
    void logDeviceInfo() const;
};
