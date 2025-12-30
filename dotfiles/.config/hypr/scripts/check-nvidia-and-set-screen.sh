#!/bin/bash

# Check if NVIDIA drivers are loaded
if lsmod | grep -q nvidia; then
    # NVIDIA drivers detected, disable screen
    ~/.config/hypr/scripts/set-screen-disabled.sh true
else
    # No NVIDIA drivers detected, use default config
    ~/.config/hypr/scripts/set-screen-disabled.sh false
fi
