#!/bin/bash
sudo nano /etc/systemd/system/ollama.service
sudo systemctl daemon-reload
sudo systemctl restart ollama
