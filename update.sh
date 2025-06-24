
#!/bin/bash

# Скрипт обновления APK Package Changer

echo "=== Обновление APK Package Changer ==="

# Остановка сервиса
echo "Остановка сервиса..."
sudo systemctl stop apk-changer

# Создание резервной копии
echo "Создание резервной копии..."
cp -r old_package old_package.backup 2>/dev/null || true
cp -r new_package new_package.backup 2>/dev/null || true
cp -r package_create package_create.backup 2>/dev/null || true
cp .env .env.backup 2>/dev/null || true
cp keystore.jks keystore.jks.backup 2>/dev/null || true

# Обновление кода
echo "Обновление кода с GitHub..."
git stash
git pull origin main

# Восстановление пользовательских файлов
echo "Восстановление пользовательских данных..."
cp -r old_package.backup/* old_package/ 2>/dev/null || true
cp -r new_package.backup/* new_package/ 2>/dev/null || true
cp -r package_create.backup/* package_create/ 2>/dev/null || true
cp .env.backup .env 2>/dev/null || true
cp keystore.jks.backup keystore.jks 2>/dev/null || true

# Обновление зависимостей
echo "Обновление Python зависимостей..."
pip3 install -r requirements.txt --upgrade

echo "Обновление Node.js зависимостей..."
npm install

# Установка прав на выполнение
chmod +x run.sh
chmod +x update.sh

# Запуск сервиса
echo "Запуск сервиса..."
sudo systemctl start apk-changer

echo "=== Обновление завершено ==="
echo "Статус сервиса: sudo systemctl status apk-changer"
