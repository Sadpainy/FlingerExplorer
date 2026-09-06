FlingerExplorer

Android System Services Research Toolkit

Overview

FlingerExplorer is a professional-grade command-line research tool designed for Android system developers, security researchers, and advanced users who need to analyze and tune the core system services of the Android platform. It provides comprehensive access to the internal state and configuration parameters of Android's fundamental services.

What It Does

FlingerExplorer targets four primary Android system services:

· SurfaceFlinger: The Android compositor responsible for rendering and display management
· AudioFlinger: The core audio service handling playback, recording, and audio routing
· InputFlinger: The input management system processing touch, keyboard, and other input events
· ActivityManager: The service managing application lifecycle, process scheduling, and memory allocation

Key Capabilities

System Analysis

· Collect and export complete dumpsys output for all target services
· Display real-time system state information
· Monitor input events and system performance metrics
· Analyze layer composition, thread states, and memory allocation

Configuration Management

· Browse comprehensive lists of system properties with descriptions and allowed values
· Modify system properties with built-in risk assessment (Low/Medium/High)
· Automatic backup of all property changes
· Restore functionality for property backups
· Support for read-only properties via resetprop when available

Research Features

· SurfaceFlinger binder service code reference
· Input device enumeration and analysis
· OOM and Low Memory Killer parameter inspection
· SELinux status monitoring and control
· System integrity verification

Platform Support

· Android versions 11 through 16
· ARM64 and x86_64 architectures
· Root access recommended for full functionality
· Read-only mode available for non-rooted devices

Technical Requirements

· Bash shell environment
· Android device with USB debugging enabled for ADB access
· Root permissions for write operations and property modifications
· Magisk or resetprop for modifying read-only (ro.*) properties

Installation and Usage

1. Push the script to the device:
   adb push FlingerExplorer.sh /data/local/tmp/
2. Set executable permissions:
   adb shell chmod +x /data/local/tmp/FlingerExplorer.sh
3. Execute the script:
   adb shell /data/local/tmp/FlingerExplorer.sh
4. Navigate the interactive menu system to access modules and features

Directory Structure

· /data/local/tmp/flinger_explorer/: Main working directory
· /data/local/tmp/flinger_explorer/backup/: Property backup storage
· Log files are timestamped and stored in the main directory

Safety Features

· Automatic backup before any property modification
· Risk level indicators for each configurable parameter
· Read-only mode for non-root users
· SELinux safety warnings and controls
· Property verification after modification attempts

Legal and Ethical Use

FlingerExplorer is intended for legitimate research, development, and debugging purposes. Users are responsible for ensuring their use complies with applicable laws and terms of service. The tool does not bypass security mechanisms or enable unauthorized access.

Limitations

· Property modifications require root access
· Some system properties may be read-only on certain devices
· Modifying critical system parameters can affect device stability
· Game anti-cheat systems may flag system modifications

Project Status

Version: 3.6.0-Stable
Supported Android: 11-16
License: Open source for research purposes
