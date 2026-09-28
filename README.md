<p align="center">
  <img src="assets/omaai-panel.png" width="100%" alt="OmaAI native Omarchy panel with model power switch, resource usage, and API endpoints">
</p>

<h1 align="center">OmaAI</h1>

<p align="center">A small Omarchy menu-bar controller for an existing llama.cpp model.</p>

## Install

Install llama.cpp and provide an existing GGUF model:

```bash
git clone https://github.com/Aayush9029/OmaAI.git
cd OmaAI
./install.sh ~/Models/your-model.gguf
```

## Use

```bash
omaai status
omaai start|stop|restart
```

The Omarchy sparkle controls the model and shows its endpoints, API key, RAM, GPU, and VRAM use.

The OpenAI-compatible API uses:

```text
Base URL: http://127.0.0.1:8080/v1
Model:    omaai
API key:  ~/.config/omaai/api-key
```

## What gets installed

```text
~/.local/bin/omaai*                       controller and launcher
~/.config/systemd/user/omaai.service      llama.cpp user service
~/.config/omarchy/plugins/io.github.aayush9029.omaai/    menu-bar plugin
~/.config/omaai/                          model path, private API key and settings
```

The native power switch remembers your choice: turning it on loads the model and enables it at login; turning it off unloads it and keeps it off after a restart. New installations start off. Reinstalling preserves the service’s on/off preference.

The panel follows the Omarchy theme and supports arrow keys (or h/j/k/l), Tab, Enter/Space, and Escape.

## Hardware profile

The launcher uses full GPU offload, Flash Attention, and one 32K-context slot. It is tested on a Framework Desktop Ryzen AI Max+ 395 / Radeon 8060S, but works with any llama.cpp-supported GPU.

Built on [llama.cpp](https://github.com/ggml-org/llama.cpp). OmaAI does not download or redistribute model weights.
