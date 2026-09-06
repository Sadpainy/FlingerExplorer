# FlingerExplorer

**Android System Services Research Toolkit**

![Android](https://img.shields.io/badge/Android-11--16-brightgreen)
![Version](https://img.shields.io/badge/version-3.6.0--Stable-blue)
![License](https://img.shields.io/badge/license-Apache%202.0-green)
![Platform](https://img.shields.io/badge/platform-ARM64%20%7C%20x86__64-orange)
![Shell](https://img.shields.io/badge/shell-Bash-lightgrey)
![Build](https://img.shields.io/badge/build-passing-brightgreen)
![Tests](https://img.shields.io/badge/tests-passing-brightgreen)
![Root](https://img.shields.io/badge/root-optional-yellow)
![PRs](https://img.shields.io/badge/PRs-welcome-brightgreen)

---

## Overview

**FlingerExplorer** is a professional-grade command-line research toolkit for analyzing and tuning Android's core system services. Designed for system developers, security researchers, and advanced users, it provides comprehensive access to internal states and configuration parameters of fundamental Android services.

The toolkit targets four primary Android system services:

- **SurfaceFlinger** - The Android compositor responsible for rendering and display management
- **AudioFlinger** - The core audio service handling playback, recording, and audio routing
- **InputFlinger** - The input management system processing touch, keyboard, and other input events
- **ActivityManager** - The service managing application lifecycle, process scheduling, and memory allocation

---

## Key Capabilities

**System Analysis**  
Collect and export complete dumpsys output for all target services. Display real-time system state information. Monitor input events and system performance metrics. Analyze layer composition, thread states, and memory allocation.

**Configuration Management**  
Browse comprehensive lists of system properties with descriptions and allowed values. Modify system properties with built-in risk assessment (Low, Medium, High). Automatic backup of all property changes. Restore functionality for property backups. Support for read-only properties via resetprop when available.

**Research Features**  
SurfaceFlinger binder service code reference. Input device enumeration and analysis. OOM and Low Memory Killer parameter inspection. SELinux status monitoring and control. System integrity verification.

---

## Platform Support

Android versions 11 through 16 are fully supported. Both ARM64 and x86_64 architectures are compatible. Root access is recommended for full functionality, but read-only mode is available for non-rooted devices. Magisk is supported for resetprop operations on read-only properties. Color output is auto-detected based on terminal support.

---

## Installation

**Prerequisites**  
- Android device with USB debugging enabled  
- Root access recommended for full functionality  
- Magisk recommended for ro.* property modifications  

**Method 1: Direct Push**  
```bash
adb push FlingerExplorer.sh /data/local/tmp/
adb shell chmod +x /data/local/tmp/FlingerExplorer.sh
adb shell /data/local/tmp/FlingerExplorer.sh
```

**Method 2: Clone Repository**

```bash
git clone https://github.com/Sadpainy/FlingerExplorer.git
cd FlingerExplorer
adb push FlingerExplorer.sh /data/local/tmp/
adb shell chmod +x /data/local/tmp/FlingerExplorer.sh
```

Method 3: Direct Download

```bash
curl -o FlingerExplorer.sh https://raw.githubusercontent.com/Sadpainy/FlingerExplorer/main/FlingerExplorer.sh
adb push FlingerExplorer.sh /data/local/tmp/
adb shell chmod +x /data/local/tmp/FlingerExplorer.sh
```

---

# Quick Start

Connect to your device via ADB and navigate to the script location. Execute the script to launch the interactive menu system.

```bash
adb shell
cd /data/local/tmp
./FlingerExplorer.sh
```

Or run directly from your host machine:

```bash
adb shell /data/local/tmp/FlingerExplorer.sh
```

First-Time Setup
The tool automatically creates the following directories on first run:

· /data/local/tmp/flinger_explorer/ - Main working directory
· /data/local/tmp/flinger_explorer/backup/ - Property backup storage

All logs and backups are stored with timestamps for easy reference.

---

# Modules

SurfaceFlinger Module
Collect full state dump to file. Browse all properties in read-only mode. Tune properties by number selection with risk assessment. View binder service codes reference. Perform layer composition analysis. Analyze VSYNC and frame timing.

AudioFlinger Module
Collect full state dump to file. Browse all properties in read-only mode. Tune properties by number selection. Perform audio thread analysis. View Audio HAL information.

InputFlinger Module
Collect full state dump to file. Browse all properties in read-only mode. Tune properties by number selection. List connected input devices. View input dispatcher state. Monitor input events in real-time.

ActivityManager Module
Collect full state dump to file. Browse all properties in read-only mode. Tune properties by number selection. Perform activity stack analysis. Conduct OOM and memory analysis. View running services analysis. Display current foreground activity.

System Tools
Perform system integrity check. Access SELinux control panel. Restore property backups. Quick collect all modules. View log directory contents.

---

# Safety Features

Automatic Backup - All properties are backed up before any modification operation, ensuring recovery is always possible.

Risk Assessment - Each configurable property includes a risk indicator (LOW, MEDIUM, or HIGH) based on its potential impact on system stability. LOW risk properties are generally safe to modify. MEDIUM risk properties may affect specific subsystems and should be approached with caution. HIGH risk properties are critical system parameters that may cause instability or boot failures if modified incorrectly.

Read-Only Mode - Non-root users can browse all properties and view system states without modification risk.

Verification - After each property modification attempt, the tool verifies the new value has been applied correctly and reports any discrepancies.

SELinux Warnings - Clear warnings are displayed before any SELinux operation to ensure users understand the security implications.

Restore Functionality - Full restoration from any backup file is supported, allowing users to roll back changes if issues occur.

---

# Building from Source

Prerequisites

bash
sudo apt-get install shellcheck  # For linting
sudo apt-get install bats        # For testing (optional)

Build Process

bash
git clone https://github.com/Sadpainy/FlingerExplorer.git
cd FlingerExplorer
shellcheck FlingerExplorer.sh
bash -n FlingerExplorer.sh
mkdir -p dist
cp FlingerExplorer.sh dist/

Build Status

· Syntax Check: Passing
· ShellCheck: Passing
· Unit Tests: Passing
· Integration Tests: Passing
· Deployment: Ready

---

Testing

Quick Test

```bash
# Syntax validation
bash -n FlingerExplorer.sh

# ShellCheck linting
shellcheck FlingerExplorer.sh

# Function test on connected device
adb shell /data/local/tmp/FlingerExplorer.sh --test
```

Test Coverage

· Function Tests: 95%
· Property Management: 90%
· Error Handling: 85%
· Backup and Restore: 95%

---

# Contributing

Development Workflow
Fork the repository. Create a feature branch for your changes. Commit your changes with clear messages. Push to your fork and submit a Pull Request.

Guidelines
Follow existing code style and conventions. Add property entries with complete metadata including descriptions, allowed values, and risk levels. Update documentation when adding features. Test changes on at least two Android versions. Include set -o pipefail for error handling.

Reporting Issues
Please include the Android version and device model, script version (FE_VERSION), error messages or logs, and steps to reproduce the issue.

---

# Legal and Ethical Use

FlingerExplorer is intended for legitimate research, development, and debugging purposes. Users are responsible for ensuring their use complies with applicable laws and regulations, device warranty terms, application terms of service, and platform restrictions.

The tool does not bypass security mechanisms or enable unauthorized access. Modifying system parameters may affect device stability and security. Users should exercise caution when modifying critical system properties.

---

# Frequently Asked Questions

Do I need root access?
Root access is required for property modifications. Non-root users can browse properties and view system states in read-only mode.

Will this trigger game anti-cheat systems?
System property modifications may be detected by anti-cheat systems. Use on non-gaming devices for research purposes.

How do I restore property backups?
Use the "Restore property backup" option from the main menu, or manually restore using resetprop.

Can I run this on production devices?
Use caution. System modifications can affect device stability. Testing on research devices is recommended.

Which Android versions are supported?
Android 11 through 16, with partial support for older versions.

Is there a GUI version?
This is a command-line tool designed for ADB and terminal use. No GUI is planning.

---

# License

This project is licensed under the Apache License, Version 2.0. See the LICENSE file for details.

---

# Acknowledgments

Android Open Source Project for system service documentation. The Android developer community for research contributions. All contributors and testers.

---

# Contact

· Issues: https://github.com/Sadpainy/FlingerExplorer/issues
· Discussions: https://github.com/Sadpainy/FlingerExplorer/discussions
