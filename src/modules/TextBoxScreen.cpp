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
#include <chrono>
#include <thread>

TextBoxScreen::TextBoxScreen(std::shared_ptr<Display> display, std::shared_ptr<InputDevice> input)
    : ScreenModule(display, input), m_shouldExit(false), m_refreshSeconds(0.0)
{
}

void TextBoxScreen::enter()
{
    Logger::debug("TextBoxScreen: Entered");

    // Reset state
    m_shouldExit = false;

    // Get refresh configuration
    m_refreshSeconds = getRefreshSeconds();

    // Initialize timing
    m_lastExecutionTime = std::chrono::steady_clock::now();

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
    // Check for user input (with short timeout for responsive input)
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

    // Handle periodic refresh if enabled
    if (m_refreshSeconds > 0.0) {
        auto now = std::chrono::steady_clock::now();
        auto timeSinceLastExecution = std::chrono::duration_cast<std::chrono::milliseconds>(now - m_lastExecutionTime);
        auto refreshIntervalMs = std::chrono::milliseconds(static_cast<long>(m_refreshSeconds * 1000));

        // Check if it's time for a refresh
        if (timeSinceLastExecution >= refreshIntervalMs) {
            Logger::debug("TextBoxScreen: Refreshing content");

            // Record start time for script execution
            auto scriptStartTime = std::chrono::steady_clock::now();

            // Update content (this executes the script)
            updateContentOnly();

            // Calculate script execution time
            auto scriptEndTime = std::chrono::steady_clock::now();
            auto scriptExecutionTime = std::chrono::duration_cast<std::chrono::milliseconds>(scriptEndTime - scriptStartTime);

            // Update last execution time
            m_lastExecutionTime = scriptStartTime;

            Logger::debug("TextBoxScreen: Script execution took " + std::to_string(scriptExecutionTime.count()) + "ms");
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

void TextBoxScreen::updateContentOnly()
{
    // Clear only the content area (lines 16, 24, 32, 40, 48)
    int contentYPositions[] = {16, 24, 32, 40, 48};
    for (int yPos : contentYPositions) {
        m_display->drawText(0, yPos, "                "); // 16 spaces to clear line
        usleep(Config::DISPLAY_CMD_DELAY);
    }

    // Execute script and get output
    std::vector<std::string> lines = executeScript();

    // Display up to 4 lines of output (lines 16, 24, 32, 40)
    int outputYPositions[] = {16, 24, 32, 40};
    for (size_t i = 0; i < lines.size() && i < 4; ++i) {
        std::string line = lines[i];

        // Truncate line if too long (16 chars max for display)
        if (line.length() > 16) {
            line = line.substr(0, 16);
        }

        // Center the text and create a 16-character padded string
        int textPos = std::max(0, (16 - static_cast<int>(line.length())) / 2);
        std::string paddedLine(16, ' '); // Create 16-space string

        // Copy the line into the centered position
        for (size_t j = 0; j < line.length(); ++j) {
            if (textPos + j < 16) {
                paddedLine[textPos + j] = line[j];
            }
        }

        m_display->drawText(0, outputYPositions[i], paddedLine);
        usleep(Config::DISPLAY_CMD_DELAY);
    }

    // If no output or error, show message
    if (lines.empty()) {
        std::string noOutput = "No output       "; // Padded to 16 chars
        m_display->drawText(0, 16, noOutput);
        usleep(Config::DISPLAY_CMD_DELAY);
    }

    // Redraw instruction at bottom
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

double TextBoxScreen::getRefreshSeconds()
{
    auto& dependencies = ModuleDependency::getInstance();
    std::string refreshStr = dependencies.getDependencyPath("textbox", "refresh_sec");

    if (refreshStr.empty()) {
        Logger::debug("No refresh_sec dependency found for textbox, using static mode");
        return 0.0;  // 0.0 means static mode (no refresh)
    }

    try {
        double refreshSeconds = std::stod(refreshStr);
        if (refreshSeconds <= 0.0) {
            Logger::debug("Invalid refresh_sec value, using static mode");
            return 0.0;
        }
        Logger::debug("TextBoxScreen: Using refresh interval: " + std::to_string(refreshSeconds) + " seconds");
        return refreshSeconds;
    } catch (const std::exception& e) {
        Logger::debug("Failed to parse refresh_sec value: " + refreshStr + ", using static mode");
        return 0.0;
    }
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