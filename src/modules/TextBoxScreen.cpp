#include "ScreenModules.h"
#include "MenuSystem.h"
#include "DeviceInterfaces.h"
#include "Config.h"
#include "Logger.h"
#include "ModuleDependency.h"
#include <iostream>
#include <unistd.h>
#include <vector>
#include <cstdio>
#include <memory>

TextBoxScreen::TextBoxScreen(std::shared_ptr<Display> display, std::shared_ptr<InputDevice> input)
    : ScreenModule(display, input), m_shouldExit(false)
{
}

void TextBoxScreen::enter()
{
    Logger::debug("TextBoxScreen: Entered");

    // Reset state
    m_shouldExit = false;

    // Execute script and display output
    executeAndDisplay();
}

void TextBoxScreen::update()
{
    // No periodic updates needed
}

void TextBoxScreen::exit()
{
    Logger::debug("TextBoxScreen: Exiting");
    // Clear display
    m_display->clear();
    usleep(Config::DISPLAY_CMD_DELAY * 3);
}

bool TextBoxScreen::handleInput()
{
    if (m_input->waitForEvents(100) > 0) {
        bool buttonPressed = false;
        bool rotationDetected = false;

        m_input->processEvents(
            [&rotationDetected](int direction) {
                // Exit on any rotation
                rotationDetected = true;
            },
            [&buttonPressed]() {
                // Exit on button press
                buttonPressed = true;
            }
        );

        // Exit on any input
        if (buttonPressed || rotationDetected) {
            return false; // Exit the screen
        }
    }

    return !m_shouldExit; // Continue running unless exit flag is set
}

void TextBoxScreen::executeAndDisplay()
{
    // Clear display
    m_display->clear();
    usleep(Config::DISPLAY_CMD_DELAY * 3);

    // Draw title (get from module configuration or use default)
    std::string title = getTitle().empty() ? "Info" : getTitle();
    int titlePos = std::max(0, (16 - static_cast<int>(title.length())) / 2);
    m_display->drawText(titlePos, 0, title);
    usleep(Config::DISPLAY_CMD_DELAY);

    // Draw separator
    m_display->drawText(0, 8, "----------------");
    usleep(Config::DISPLAY_CMD_DELAY);

    // Execute script and get output
    std::vector<std::string> lines = executeScript();

    // Display up to 4 lines of output (lines 16, 24, 32, 40)
    int yPositions[] = {16, 24, 32, 40};
    for (size_t i = 0; i < lines.size() && i < 4; ++i) {
        std::string line = lines[i];

        // Truncate line if too long (16 chars max for display)
        if (line.length() > 16) {
            line = line.substr(0, 16);
        }

        // Center the text
        int textPos = std::max(0, (16 - static_cast<int>(line.length())) / 2);
        m_display->drawText(textPos, yPositions[i], line);
        usleep(Config::DISPLAY_CMD_DELAY);
    }

    // If no output or error, show message
    if (lines.empty()) {
        m_display->drawText(0, 16, "No output");
        usleep(Config::DISPLAY_CMD_DELAY);
    }

    // Draw instruction at bottom
    m_display->drawText(0, 48, "Press to return");
    usleep(Config::DISPLAY_CMD_DELAY);
}

std::vector<std::string> TextBoxScreen::executeScript()
{
    std::vector<std::string> lines;

    // Get script path from configuration
    std::string scriptPath = getScriptPath();
    if (scriptPath.empty()) {
        lines.push_back("Error: No script");
        return lines;
    }

    // Execute the script and capture output
    std::unique_ptr<FILE, decltype(&pclose)> pipe(
        popen(scriptPath.c_str(), "r"), pclose);

    if (!pipe) {
        lines.push_back("Error: Script failed");
        return lines;
    }

    // Read script output line by line
    char buffer[128];
    while (fgets(buffer, sizeof(buffer), pipe.get()) != nullptr) {
        std::string line(buffer);

        // Remove trailing newline
        if (!line.empty() && line.back() == '\n') {
            line.pop_back();
        }

        // Skip empty lines
        if (!line.empty()) {
            lines.push_back(line);
        }
    }

    return lines;
}

std::string TextBoxScreen::getScriptPath()
{
    auto& dependencies = ModuleDependency::getInstance();
    std::string scriptPath = dependencies.getDependencyPath("textbox", "script_path");

    if (scriptPath.empty()) {
        Logger::debug("No script_path dependency found for textbox, using default");
        return "/usr/bin/micropanel-version.sh";  // fallback default
    }

    Logger::debug("TextBoxScreen: Using script path: " + scriptPath);
    return scriptPath;
}

std::string TextBoxScreen::getTitle()
{
    auto& dependencies = ModuleDependency::getInstance();
    std::string title = dependencies.getDependencyPath("textbox", "display_title");

    if (title.empty()) {
        Logger::debug("No display_title dependency found for textbox, using default");
        return "Info";  // fallback default
    }

    return title;
}

// GPIO support methods
void TextBoxScreen::handleGPIORotation(int direction) {
    // Exit on any GPIO rotation
    m_shouldExit = true;
}

bool TextBoxScreen::handleGPIOButtonPress() {
    // Exit on GPIO button press
    return false;
}