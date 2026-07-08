
# Problem Step Recorder Plus Plus

This is a modernized, high-performance replacement for Microsoft's Problem Steps Recorder (PSR), which was discontinued in newer Windows versions. PSR was a valuable tool that IT professionals and everyday users relied on to document technical issues. PSR++ fills that gap, acting as a super-powered version of the Windows Snipping Tool equipped with advanced tracking, automated storage, and an interactive modern interface. 

---

<img width="1045" height="695" alt="image" src="https://github.com/user-attachments/assets/f10a2e16-96c0-4e3c-aed1-28a00c4eb6d9" />

## 📖 The Backstory

**What Was PSR?**
A built-in Windows utility that recorded step-by-step actions to document computer problems for tech support. It automatically captured screenshots of each click and generated an MHTML report. It was an unsung hero in enterprise IT departments.

**Why PSR++ Was Created**
PSR's discontinuation left users and organizations without a native, reliable alternative. Support teams still require detailed problem documentation, and end-users need a simple way to show what they are seeing. PSR++ was built to not only replace the original tool but to vastly improve upon it by giving you more control over the capture process, highly organized output, and a completely modernized capability set.

---

## ✨ Key Features & Capabilities

PSR++ goes far beyond standard print-screen functionality. 

### 📸 Intelligent Capture Modes
* **Single Capture:** Fire a precise screenshot with a built-in delay timer for perfect framing.
* **Continuous Capture:** Start a loop that automatically snaps off-focus hardware input events (every time you click), debounced to prevent duplicate images. Press `ESC` to stop.
* **Smart Bounds:** Choose to capture the entire physical desktop viewport or automatically clip strictly to the targeted window underneath your cursor.

### 🎯 Visual Enhancements & Tracking
* **Hardware Cursor Capture:** Visually record the actual Windows cursor state.
* **Mouse Highlighting:** Draw highly customizable, translucent highlights directly over click coordinates to make instructions crystal clear.
* **Window Outlining:** Automatically draw a customizable border around the active element or window you are interacting with.
* **Complete Style Control:** Sliders and color-pickers to adjust outline width, highlight size, colors, and opacity levels. 

### 🖥️ Modern UI & Workflow
* **Session History Sidebar:** An interactive, collapsible sidebar that dynamically populates with thumbnails of your current session's captures. 
* **Auto-Clipboard Synchronization:** Every capture (and every click of a history thumbnail) automatically copies the high-res image directly to your OS clipboard.
* **True DPI-Awareness:** Deep GDI hardware integration bypasses Windows scaling virtualization. Whether you are on a 100% or 150% scaled display, captures are mapped 1:1 to physical pixels without clipping or blurring.
* **Persistent Configuration:** Automatically saves your UI preferences, colors, and slider values to an `.ini` file so your tool is ready exactly how you left it.

### 📁 Organized Storage
* **Automatic Directory Creation:** Generates a primary `Screenshots` folder in your Pictures directory.
* **Session-Based Subfolders:** Every time you launch PSR++, it creates a unique `YYMMDD_HHMMSS` folder.
* **Sequential Naming:** Captures are automatically numbered and timestamped (e.g., `01-26.06.12_19.45.00.png`) so you never lose track of a sequence.

---

## 🎯 Who Is It For?

**For Professional Use**
Perfect for IT and support teams who need to:
* Create rigorous technical documentation.
* Record step-by-step work procedures and user guides.
* Conduct Quality Assurance (QA) software audits and visual bug reporting.
* Generate visual training materials.

**For Regular Users**
Better than basic Print Screen when you need to:
* Show someone exactly how to perform a task on a computer.
* Save sequential proof of something you saw on screen.
* Quickly report an error to a helpdesk without having to manually paste and save multiple images.

---

## ⚙️ Technical Components

Under the hood, PSR++ is a highly optimized, lightweight script requiring no heavy installations:
* **Core:** Written entirely in Windows PowerShell 5.1+.
* **Interface:** Built on Windows Presentation Foundation (WPF) with strict anti-aliasing configurations (`UseLayoutRounding`, `SnapsToDevicePixels`).
* **API Integration:** Leverages heavy C# P/Invoke definitions to access `user32.dll` and `gdi32.dll`. This allows for off-focus hardware keystroke detection (`GetAsyncKeyState`), raw screen coordinate handling, and deep window hierarchy traversal (`GetAncestor`).
* **Portability:** Includes base64-encoded embedded icon data—no external image assets required.

---
