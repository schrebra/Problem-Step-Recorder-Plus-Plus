
# PSR++

![image](https://github.com/user-attachments/assets/559dcd44-2e3c-462c-aa6d-b181d28d78b2)

![06-24 11 17_10 50 57](https://github.com/user-attachments/assets/25da6ee1-73a6-4cef-9f8d-71a8b68c0e51)

![09-24 11 17_11 00 59](https://github.com/user-attachments/assets/e67dcf43-d2ee-4c8e-bff1-d9b9a72077a2)


## Background
This is a modernized replacement for Microsoft's Problem Steps Recorder (PSR), which was discontinued in newer Windows versions. PSR was a valuable tool that IT professionals and users relied on to document technical issues.

## What Was PSR?
- A built-in Windows tool that recorded step-by-step actions
- Used to document computer problems for tech support
- Automatically captured screenshots of each action
- Created an MHTML report with images and descriptions
- Widely used in enterprise IT departments

## Why PSR++ Was Created
1. Fill the Gap
   - PSR's discontinuation left many users without a reliable alternative
   - Organizations still need a way to document technical issues
   - Support teams require detailed problem documentation

2. Improved Features
   - More control over capturing process
   - Better organization of screenshots
   - Enhanced mouse tracking and highlighting
   - Modern interface and capabilities
   - More flexible output options

Think of it like a super-powered version of the Windows Snipping Tool, but with extra features that make it especially useful for anyone who needs to regularly document things they're doing on their computer.

## What It Does
This is a powerful screenshot tool that lets you:
- Take screenshots of your screen or specific windows
- Highlight where your mouse is pointing
- Capture multiple screenshots automatically
- Save screenshots in organized folders by date/time

## Why It's Useful

### For Regular Users
- Better than basic Print Screen when you need to:
  - Document steps in a process
  - Show someone how to do something on a computer
  - Save proof of something you saw on screen
  - Create training materials
  - Report software bugs

### For Professional Use
- Perfect for:
  - Creating technical documentation
  - Making user guides
  - Recording work procedures
  - Quality assurance testing
  - Customer support interactions
  - Training materials

### Key Benefits
1. Organized Storage
   - Automatically saves files in dated folders
   - Never lose track of your screenshots

2. Flexible Capture Options
   - Take one screenshot or many
   - Choose exactly what to capture
   - Show where your mouse is pointing

3. Professional Features
   - Timer options for perfect timing
   - Mouse highlighting for clear instructions
   - Clean, organized output


## Core Features
- Advanced screenshot capture capabilities
- Mouse cursor highlighting and tracking
- Customizable capture settings
- Session-based screenshot organization
- Multiple capture modes (single/continuous)

## Technical Components
1. Windows API Integration
   - User32.dll imports for window/cursor management
   - Screen coordinate handling
   - Window detection and manipulation

2. Global Settings
   - Screenshot storage path management
   - Capture session tracking
   - Mouse highlight customization
   - Capture counter and session ID generation

3. Capture Options
   - Countdown timer functionality
   - Continuous capture mode
   - Mouse cursor visualization
   - Highlight colors and opacity settings
   - Custom outline colors

4. File Management
   - Automatic directory creation
   - Session-based folder organization
   - Screenshot naming conventions

## Implementation Details
- Written in PowerShell
- Uses Windows Forms and Drawing assemblies
- Leverages P/Invoke for native Windows API calls
- Includes base64-encoded icon data
- Implements strict mode for error handling

## Future Change Log
- [Fix] - Remove small boarder around screenshots
- [Feature] - Add screenshot outline color and size. Include toggle as well
- [Improvement] - Hide preview pane until screenshot is captured
- [Feature] - Include settings menu bar to export profile configured settings to program path.
- [Feature] - Include settings menu bar for import configured profile settings.
- [Feature] - Create cfg file for overall settings to auto import from last session
- [Bug] - Fix clipboard screenshot when copying into markdown - It slightly shrinks the screenshot


