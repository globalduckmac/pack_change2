
#!/bin/bash

# Скрипт обновления APK Package Changer

echo "=== Обновление APK Package Changer ==="

# Остановка сервиса
echo "Остановка сервиса..."
sudo systemctl stop apk-changer

# Обновление кода
echo "Обновление кода с GitHub..."
git pull origin main

# Обновление зависимостей
echo "Обновление зависимостей..."
pip3 install -r requirements.txt
npm install

# Запуск сервиса
echo "Запуск сервиса..."
sudo systemctl start apk-changer

echo "=== Обновление завершено! ==="
echo "Статус сервиса: $(sudo systemctl is-active apk-changer)"
