
#!/bin/bash

# Скрипт развертывания APK Package Changer на Ubuntu 22
# Использование: chmod +x deploy.sh && ./deploy.sh

set -e

echo "=== Установка APK Package Changer ==="

# Обновление системы
echo "Обновление системы..."
sudo apt update && sudo apt upgrade -y

# Установка основных зависимостей
echo "Установка основных зависимостей..."
sudo apt install -y \
    git \
    curl \
    wget \
    unzip \
    python3 \
    python3-pip \
    python3-venv \
    nodejs \
    npm \
    default-jdk \
    build-essential \
    zip \
    unzip \
    aapt \
    zipalign

# Установка инструментов Android
echo "Скачивание Android Build Tools..."
if [ ! -d "/opt/android-build-tools" ]; then
    wget -q https://dl.google.com/android/repository/build-tools_r34.0.0-linux.zip -O build-tools.zip
    unzip -q build-tools.zip
    sudo mv android-* /opt/android-build-tools
    sudo chmod +x /opt/android-build-tools/*/zipalign
    sudo chmod +x /opt/android-build-tools/*/apksigner
    rm build-tools.zip
fi

# Скачивание apktool
echo "Скачивание apktool..."
if [ ! -f "/usr/local/bin/apktool" ]; then
    wget -q https://raw.githubusercontent.com/iBotPeaches/Apktool/master/scripts/linux/apktool -O apktool
    wget -q https://bitbucket.org/iBotPeaches/apktool/downloads/apktool_2.9.3.jar -O apktool.jar
    sudo mv apktool apktool.jar /usr/local/bin/
    sudo chmod +x /usr/local/bin/apktool
fi

# Клонирование репозитория
echo "Клонирование репозитория..."
REPO_URL="https://github.com/YOUR_USERNAME/YOUR_REPO_NAME.git"
PROJECT_DIR="apk-package-changer"

if [ -d "$PROJECT_DIR" ]; then
    echo "Папка проекта уже существует, обновляем..."
    cd $PROJECT_DIR
    git pull
else
    git clone $REPO_URL $PROJECT_DIR
    cd $PROJECT_DIR
fi

# Установка Python зависимостей
echo "Установка Python зависимостей..."
pip3 install -r requirements.txt

# Установка Node.js зависимостей
echo "Установка Node.js зависимостей..."
npm install

# Создание .env файла
echo "Создание конфигурации..."
cat > .env << 'EOF'
JAVA_PATH=/usr/bin/java
ZIPALIGN_PATH=/opt/android-build-tools/34.0.0/zipalign
APKSIGNER_PATH=/opt/android-build-tools/34.0.0/apksigner
KEYSTORE_NAME=keystore.jks
KEY_ALIAS=mykey
KEYSTORE_PASSWORD=123456
KEY_PASSWORD=123456
EOF

# Создание keystore если его нет
if [ ! -f "keystore.jks" ]; then
    echo "Создание keystore..."
    keytool -genkey -v -keystore keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias mykey \
        -dname "CN=APK Changer, OU=Dev, O=Company, L=City, S=State, C=US" \
        -storepass 123456 -keypass 123456
fi

# Создание папок
mkdir -p old_package new_package package_create

# Установка прав на выполнение скриптов
chmod +x run.sh
chmod +x update.sh

# Создание systemd сервиса
echo "Создание systemd сервиса..."
sudo tee /etc/systemd/system/apk-changer.service > /dev/null << EOF
[Unit]
Description=APK Package Changer Web Service
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$(pwd)
Environment=PATH=/usr/bin:/usr/local/bin:/opt/android-build-tools/34.0.0
ExecStart=/usr/bin/python3 app.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Запуск и включение сервиса
echo "Запуск сервиса..."
sudo systemctl daemon-reload
sudo systemctl enable apk-changer
sudo systemctl start apk-changer

echo "=== Установка завершена ==="
echo "Веб-панель доступна по адресу: http://localhost:5000"
echo "Статус сервиса: sudo systemctl status apk-changer"
echo "Логи сервиса: sudo journalctl -u apk-changer -f"
