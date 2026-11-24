# Live Text

Enable **live text** in Settings → Features. Move the pointer to the display you want to read and press **Super+Shift+T**. Galaga freezes that entire output and recognises its text locally. A top-center banner uses the same tile and entrance animation as a battery alert. It stays visible until you exit Live Text. Right-click for the language control when multiple OCR packs are installed. When the pointer turns into an I-beam, drag across words and press Ctrl+C. Esc dismisses the overlay.

Ctrl+A selects all recognised words. Left/right selects a word and Shift extends the selection. Right-click a word or press Shift+F10 for copy, translation and word search. Email and phone actions appear for recognised addresses and numbers when the corresponding desktop handler is installed. Translation and search send the selected text to the named site when chosen.

The shortcut in `config/hypr/hyprland/keybinds.lua` reaches the feature-gated loader in `shell.qml`. The overlay in `inspect/Inspect.qml` starts `inspect/worker.py`, which captures the output with grim into an anonymous memory file. Tesseract returns word boxes and reading order for that frame. Pointer hit-testing and selection highlights use the actual frame and overlay dimensions. If several OCR languages are installed, the language control rereads the same frame.

This works with visible photos, documents, browser content and paused video. Capture and recognition stop on close or disable. A frozen frame stays fixed while the app underneath changes; reopen Live Text for a new frame. The existing screenshot tool retains its separate region OCR action.
