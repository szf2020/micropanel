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
#include <map>

TextBoxScreen::TextBoxScreen(std::shared_ptr<Display> display, std::shared_ptr<InputDevice> input)
    : ScreenModule(display, input), m_shouldExit(false), m_refreshSeconds(0.0), m_moduleId("textbox")
{
}

void TextBoxScreen::enter()
{
    Logger::debug("TextBoxScreen: Entered");

    // Reset state
    m_shouldExit = false;
    m_previousContent.clear(); // Clear previous content for fresh start

    // Get refresh configuration
    m_refreshSeconds = getRefreshSeconds();
    Logger::debug("TextBoxScreen (" + m_moduleId + "): Configured refresh interval: " + std::to_string(m_refreshSeconds) + " seconds");

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

        // Debug timing information (only every 10th check to reduce spam)
        static int debugCounter = 0;
        if (++debugCounter % 10 == 0) {
            Logger::debug("TextBoxScreen (" + m_moduleId + "): Time since last execution: " + std::to_string(timeSinceLastExecution.count()) + "ms, interval: " + std::to_string(refreshIntervalMs.count()) + "ms");
        }

        // Check if it's time for a refresh
        if (timeSinceLastExecution >= refreshIntervalMs) {
            Logger::debug("TextBoxScreen (" + m_moduleId + "): Refreshing content");

            // Record start time for script execution
            auto scriptStartTime = std::chrono::steady_clock::now();

            // Update content (this executes the script)
            updateContentOnly();

            // Calculate script execution time
            auto scriptEndTime = std::chrono::steady_clock::now();
            auto scriptExecutionTime = std::chrono::duration_cast<std::chrono::milliseconds>(scriptEndTime - scriptStartTime);

            // Update last execution time
            m_lastExecutionTime = scriptStartTime;

            Logger::debug("TextBoxScreen (" + m_moduleId + "): Script execution took " + std::to_string(scriptExecutionTime.count()) + "ms");
        }
    } else {
        Logger::debug("TextBoxScreen (" + m_moduleId + "): Static mode - no refresh configured");
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

        // Center the text and create a 16-character padded string (same as updateSingleLine)
        int textPos = std::max(0, (16 - static_cast<int>(line.length())) / 2);
        std::string paddedLine(16, ' '); // Create 16-space string filled with spaces
        // Copy the line into the centered position
        for (size_t j = 0; j < line.length(); ++j) {
            if (textPos + j < 16) {
                paddedLine[textPos + j] = line[j];
            }
        }
        m_display->drawText(0, yPositions[i], paddedLine);
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
    // Execute script and get new output
    std::vector<std::string> newLines = executeScript();

    // Compare with previous content and update only changed lines
    updateChangedLinesOnly(newLines);

    // Store current content for next comparison
    m_previousContent = newLines;
}

void TextBoxScreen::updateChangedLinesOnly(const std::vector<std::string>& newLines)
{
    // Content display positions (up to 4 lines: 16, 24, 32, 40)
    int contentYPositions[] = {16, 24, 32, 40};
    const size_t maxDisplayLines = 4;

    // Compare each line position (0-3) and update only if changed
    for (size_t i = 0; i < maxDisplayLines; ++i) {
        std::string newLine = (i < newLines.size()) ? newLines[i] : "";
        std::string oldLine = (i < m_previousContent.size()) ? m_previousContent[i] : "";

        // Only update this line if content changed
        if (newLine != oldLine) {
            Logger::debug("TextBoxScreen (" + m_moduleId + "): Updating line " + std::to_string(i) + ": '" + newLine + "'");
            updateSingleLine(i, newLine, contentYPositions[i]);
        }
    }

    // Handle the case where new output has fewer lines than before
    // Clear any leftover lines from previous longer output
    if (newLines.size() < m_previousContent.size()) {
        for (size_t i = newLines.size(); i < m_previousContent.size() && i < maxDisplayLines; ++i) {
            Logger::debug("TextBoxScreen (" + m_moduleId + "): Clearing line " + std::to_string(i));
            updateSingleLine(i, "", contentYPositions[i]); // Clear line
        }
    }

    // Update "No output" message if needed
    bool hadContent = !m_previousContent.empty();
    bool hasContent = !newLines.empty();

    if (hadContent != hasContent) {
        if (!hasContent) {
            // Show "No output" message
            Logger::debug("TextBoxScreen (" + m_moduleId + "): Showing 'No output' message");
            updateSingleLine(0, "No output", contentYPositions[0]);
        }
        // If we now have content, the lines above will be updated naturally
    }
}

void TextBoxScreen::updateSingleLine(size_t lineIndex, const std::string& content, int yPosition)
{
    std::string line = content;

    // Replace UTF-8 degree symbol with ASCII equivalent
    line = replaceUnicodeChars(line);

    // Truncate line if too long (16 chars max for display)
    if (line.length() > 16) {
        line = line.substr(0, 16);
    }

    // Center the text and create a 16-character padded string
    int textPos = std::max(0, (16 - static_cast<int>(line.length())) / 2);
    std::string paddedLine(16, ' '); // Create 16-space string filled with spaces

    // Copy the line into the centered position
    for (size_t j = 0; j < line.length(); ++j) {
        if (textPos + j < 16) {
            paddedLine[textPos + j] = line[j];
        }
    }

    // Update only this single line
    m_display->drawText(0, yPosition, paddedLine);
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
    std::string scriptPath = dependencies.getDependencyPath(m_moduleId, "script_path");

    if (scriptPath.empty()) {
        Logger::debug("No script_path dependency found for " + m_moduleId + ", using default");
        return "/usr/bin/micropanel-version.sh";  // fallback default
    }

    // Apply runtime parameter substitution
    scriptPath = substituteParameters(scriptPath);

    Logger::debug("TextBoxScreen: Using script path: " + scriptPath);
    return scriptPath;
}

std::string TextBoxScreen::getTitle()
{
    auto& dependencies = ModuleDependency::getInstance();
    std::string title = dependencies.getDependencyPath(m_moduleId, "display_title");

    if (title.empty()) {
        Logger::debug("No display_title dependency found for " + m_moduleId + ", using default");
        return "Info";  // fallback default
    }

    // Apply runtime parameter substitution
    title = substituteParameters(title);

    return title;
}

double TextBoxScreen::getRefreshSeconds()
{
    auto& dependencies = ModuleDependency::getInstance();
    std::string refreshStr = dependencies.getDependencyPath(m_moduleId, "refresh_sec");

    if (refreshStr.empty()) {
        Logger::debug("No refresh_sec dependency found for " + m_moduleId + ", using static mode");
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

void TextBoxScreen::setId(const std::string& id) {
    m_moduleId = id;
    Logger::debug("TextBoxScreen: Set dynamic ID to: " + id);
}

void TextBoxScreen::setRuntimeParameters(const std::map<std::string, std::string>& params) {
    m_runtimeParams = params;
    Logger::debug("TextBoxScreen (" + m_moduleId + "): Set " + std::to_string(params.size()) + " runtime parameters");

    // Debug: Log all parameters
    for (const auto& param : params) {
        Logger::debug("  " + param.first + " = " + param.second);
    }
}

std::string TextBoxScreen::replaceUnicodeChars(const std::string& input) {
    std::string result = input;

    // Replace UTF-8 degree symbol (°) with ASCII equivalent
    // The degree symbol in UTF-8 is: 0xC2 0xB0
    size_t pos = 0;
    while ((pos = result.find("\xC2\xB0", pos)) != std::string::npos) {
        result.replace(pos, 2, "*");  // Replace with asterisk
        pos += 1;  // Move past the replacement
    }

    // Add more Unicode replacements as needed
    // Example: Replace other common symbols
    // while ((pos = result.find("µ", pos)) != std::string::npos) {
    //     result.replace(pos, 2, "u");
    //     pos += 1;
    // }

    return result;
}

std::string TextBoxScreen::substituteParameters(const std::string& input) {
    std::string result = input;

    // Replace all $PARAMETER placeholders with runtime parameter values
    for (const auto& param : m_runtimeParams) {
        std::string placeholder = "$" + param.first;
        size_t pos = 0;

        while ((pos = result.find(placeholder, pos)) != std::string::npos) {
            result.replace(pos, placeholder.length(), param.second);
            pos += param.second.length();

            Logger::debug("TextBoxScreen: Substituted " + placeholder + " → " + param.second);
        }
    }

    return result;
}