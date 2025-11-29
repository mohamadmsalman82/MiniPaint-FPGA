 🎨 MINI Paint — FPGA Drawing Application  
*A hardware-accelerated MS-Paint–style drawing tool for the DE1-SoC FPGA*  
_By Mohamad Salman & Tawfiq Shnoudeh_  
:contentReference[oaicite:0]{index=0}

![Build](https://img.shields.io/badge/Hardware-FPGA-blue?style=flat-square)
![VGA](https://img.shields.io/badge/Display-640x480%20VGA-purple?style=flat-square)
![PS2](https://img.shields.io/badge/Input-PS%2F2%20Mouse-green?style=flat-square)
![Language](https://img.shields.io/badge/Language-Verilog-yellow?style=flat-square)
![Status](https://img.shields.io/badge/Status-Completed-brightgreen?style=flat-square)

---

## 📌 Overview
MINI Paint is a fully hardware-driven drawing program built on the **DE1-SoC FPGA**, using a **PS/2 mouse** for input and **VGA** for display. It provides real-time cursor movement, multiple drawing tools, custom UI graphics, and smooth pixel rendering — all implemented in Verilog with no software processing.

This project recreates a simplified MS Paint experience entirely in FPGA logic.

---

## ✨ Features
- ✔ Real-time drawing using a PS/2 mouse  
- ✔ Smooth cursor with overflow & boundary handling  
- ✔ Custom background + toolbar stored in ROM  
- ✔ Color selection using 9-bit switches  
- ✔ Multiple drawing tools  
- ✔ Accurate toolbar lockout to prevent accidental overwrites  

### 🎯 Tools Implemented
- **Pen Tool** (variable thickness)  
- **Eraser Tool** (size-matched)  
- **Box Tool** (drag to draw rectangle)  
- **Fill Tool**  
- **Screen Reset**  
- **Size + / – Buttons**  

---

## 🧠 Architecture Overview  
The hardware system is composed of:

### 🔹 Core Components  
- **Main FSM** (drawing logic, tool selection, color mode)  
- **PS/2 Mouse Decoder**  
- **Cursor Engine + Cursor ROM**  
- **Pen / Eraser / Box / Fill Engines**  
- **Background + Toolbar ROMs**  
- **VGA MUX + VGA Adapter (640×480)**  

All modules work in sync to update the framebuffer using pixel-level write control.

(Diagrams referenced from presentation)  
:contentReference[oaicite:1]{index=1}

---

## ▶️ Controls  
| Action | Control |
|--------|---------|
| Draw | **Left Click + KEY[3]** |
| Reset Screen | **KEY[0]** |
| Change Color | Set **SW[8:0]** → Press **KEY[1]** |
| Draw Box | Hold **KEY[3]**, drag, release |
| Tool Display | **HEX3** (0=Box, 1=Pen, 2=Eraser, 3=Fill) |
| Size Display | **HEX0–HEX2** |

---

## 🧪 Testing & Debugging

### ✔ Testing Performed  
- ModelSim simulation of FSMs  
- XY packet decoding on VGA output  
- Pixel + cursor alignment verification  
- Continuous line stability & boundary tests  
- Size switching tests (pen/eraser)  
- Toolbar lockout checks  
- MIF redraw validation  
- Stress tests (fast motion, rapid clicking, long sessions)  
:contentReference[oaicite:2]{index=2}

### 🐞 Major Bugs Fixed  
- Rectangle tool ending issues → KEY-confirm fix  
- Pen size snapping → added update-rate limiter  
- Drawing on toolbar → clamped drawing region  
- Toolbar not resetting → forced ROM redraw  
- Flipped cursor → fixed sprite orientation  
- Accidental draws → required Left Click + KEY[3]  
- Eraser size/color issues → unified size register & color buffer  
- Out-of-bounds drawing → tightened clamping  
:contentReference[oaicite:3]{index=3}

---

## 🚀 Future Improvements  
- Live rectangle preview  
- Circular pens  
- Better flood-fill  
- Selection, copy/paste  
- Textbox tool  
- Cursor intersection preview  
:contentReference[oaicite:4]{index=4}

---

## 👥 Contributors  

### **Mohamad Salman**  
- VGA rendering & graphics pipeline  
- Background + toolbar MIF design  
- Mouse input & drawing-memory interfacing  
- FSM for tool/color selection & toolbar lockout  
- Size adjustment logic  
- Rectangle tool implementation  
- Full-system integration & debugging  
:contentReference[oaicite:5]{index=5}

### **Tawfiq Shnoudeh**  
- Full PS/2 mouse controller  
- Movement overflow handling  
- Left/middle/right click detection  
- FSM rules for drawing restrictions  
- Key-confirm logic  
- Screen reset & background preservation  
- Color preview + cursor guides  
- Bucket fill implementation  
:contentReference[oaicite:6]{index=6}

---

## 📂 Repository Structure (Suggested)

/src
/vga
/ps2
/tools
/fsm
/resources
background.mif
toolbar.mif
/docs
presentation.pdf
README.md
