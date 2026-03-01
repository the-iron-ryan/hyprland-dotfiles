#!/bin/bash

# Check if NVIDIA drivers are loaded
if lsmod | grep -q nvidia; then
    # NVIDIA drivers detected, disable screen
    echo "NVIDIA drivers detected. Disabling screen."
    /home/the-iron-ryan/.mydotfiles/com.ml4w.the-iron-ryan.dotfiles/.config/hypr/scripts/set-screen-disabled.sh true
else
    # No NVIDIA drivers detected, use default config
    echo "No NVIDIA drivers detected. Using default screen configuration."
    /home/the-iron-ryan/.mydotfiles/com.ml4w.the-iron-ryan.dotfiles/.config/hypr/scripts/set-screen-disabled.sh false
fi
