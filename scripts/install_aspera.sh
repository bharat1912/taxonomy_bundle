#!/bin/bash
# Aspera Connect Installation Script for Taxonomy Bundle

if command -v ascp &> /dev/null; then
    echo -e "\033[0;32m[SKIP] Aspera Connect is already installed.\033[0m"
else
    OS=$(uname -s)
    echo "Detected OS: $OS. Starting download..."
    
    if [ "$OS" = "Darwin" ]; then
        curl -O https://download.asperasoft.com/download/sw/connect/4.2.6/ibm-aspera-connect-4.2.6.223.dmg
        hdiutil attach ibm-aspera-connect-4.2.6.223.dmg
        sudo "/Volumes/Aspera Connect/Install Aspera Connect.app/Contents/Resources/install_dir.sh" -f --install-dir=/usr/local/aspera
        hdiutil detach "/Volumes/Aspera Connect"
        rm ibm-aspera-connect-4.2.6.223.dmg
    elif [ "$OS" = "Linux" ]; then
        curl -O https://download.asperasoft.com/download/sw/connect/4.2.6/ibm-aspera-connect-4.2.6.223.tar.gz
        tar -xvf ibm-aspera-connect-4.2.6.223.tar.gz
        ./ibm-aspera-connect-4.2.6.223.sh
        rm ibm-aspera-connect-4.2.6.223.tar.gz
    else
        echo -e "\033[0;31m[ERROR] Unsupported OS. Please install Aspera Connect manually.\033[0m"
        exit 1
    fi
fi
