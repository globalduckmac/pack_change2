
#!/bin/bash

# Скрипт развертывания APK Package Changer на Ubuntu 22
# Использование: chmod +x deploy.sh && ./deploy.sh

set -e

echo "=== Установка APK Package Changer ==="

# Скрипт может запускаться от любого пользователя

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
    zipalign \
    python3-dev \
    python3-setuptools \
    software-properties-common

# Обновление pip
echo "Обновление pip..."
python3 -m pip install --upgrade pip

# Установка Android SDK Tools
echo "Установка Android Build Tools..."
ANDROID_HOME="/opt/android-sdk"
BUILD_TOOLS_VERSION="34.0.0"

if [ ! -d "$ANDROID_HOME" ]; then
    sudo mkdir -p $ANDROID_HOME
    sudo chown $USER:$USER $ANDROID_HOME
    
    # Скачиваем command line tools
    wget -q https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip -O cmdline-tools.zip
    unzip -q cmdline-tools.zip -d $ANDROID_HOME
    mv $ANDROID_HOME/cmdline-tools $ANDROID_HOME/cmdline-tools-latest
    mkdir -p $ANDROID_HOME/cmdline-tools
    mv $ANDROID_HOME/cmdline-tools-latest $ANDROID_HOME/cmdline-tools/latest
    rm cmdline-tools.zip
    
    # Устанавливаем build-tools
    yes | $ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager "build-tools;$BUILD_TOOLS_VERSION" "platform-tools"
fi

# Скачивание apktool
echo "Установка apktool..."
APKTOOL_DIR="/usr/local/bin"
if [ ! -f "$APKTOOL_DIR/apktool.jar" ]; then
    wget -q https://raw.githubusercontent.com/iBotPeaches/Apktool/master/scripts/linux/apktool -O /tmp/apktool
    wget -q https://bitbucket.org/iBotPeaches/apktool/downloads/apktool_2.9.3.jar -O /tmp/apktool.jar
    sudo mv /tmp/apktool /tmp/apktool.jar $APKTOOL_DIR/
    sudo chmod +x $APKTOOL_DIR/apktool
    sudo ln -sf $APKTOOL_DIR/apktool.jar $APKTOOL_DIR/apktool.jar
fi

# Определяем директорию проекта
PROJECT_DIR="$HOME/apk-package-changer"

# Клонирование или обновление репозитория
echo "Подготовка проекта..."
if [ -d "$PROJECT_DIR" ]; then
    echo "Папка проекта уже существует, очищаем..."
    rm -rf $PROJECT_DIR
fi

# Создаем проект из текущих файлов (если мы в Replit)
mkdir -p $PROJECT_DIR
cd $PROJECT_DIR

# Создаем структуру проекта
echo "Создание структуры проекта..."
mkdir -p old_package new_package package_create templates

# Создаем основной Python файл
cat > app.py << 'PYEOF'
from flask import Flask, render_template, request, jsonify, send_file, redirect, url_for, flash
import os
import subprocess
import zipfile
import json
from datetime import datetime
import threading
import time

app = Flask(__name__)
app.secret_key = 'your-secret-key-here-change-in-production'

# Создаем необходимые папки
os.makedirs('old_package', exist_ok=True)
os.makedirs('new_package', exist_ok=True)
os.makedirs('package_create', exist_ok=True)

# Глобальная переменная для процесса
process_output = []
process_running = False

def run_shell_command():
    global process_output, process_running
    process_output = []
    process_running = True
    
    try:
        process = subprocess.Popen(['bash', 'run.sh'], 
                                 stdout=subprocess.PIPE, 
                                 stderr=subprocess.STDOUT, 
                                 universal_newlines=True,
                                 bufsize=1)
        
        for line in iter(process.stdout.readline, ''):
            process_output.append(line.strip())
            
        process.wait()
        process_output.append("Процесс завершен!")
        
    except Exception as e:
        process_output.append(f"Ошибка: {str(e)}")
    finally:
        process_running = False

@app.route('/')
def index():
    apk_files = []
    if os.path.exists('old_package'):
        apk_files = [f for f in os.listdir('old_package') if f.endswith('.apk')]
    
    result_exists = os.path.exists('package_create/result.txt')
    used_exists = os.path.exists('package_create/used.txt')
    
    return render_template('index.html', 
                         apk_files=apk_files, 
                         result_exists=result_exists,
                         used_exists=used_exists)

@app.route('/generate_packages', methods=['POST'])
def generate_packages():
    try:
        count = int(request.form.get('count', 10))
        
        result = subprocess.run(['python3', 'package_create/create_packeges.py'], 
                              input=str(count), 
                              text=True, 
                              capture_output=True)
        
        if result.returncode == 0:
            save_to_history(count)
            flash(f'Успешно сгенерировано {count} пакетов!', 'success')
        else:
            flash(f'Ошибка при генерации: {result.stderr}', 'error')
    except Exception as e:
        flash(f'Ошибка: {str(e)}', 'error')
    
    return redirect(url_for('index'))

@app.route('/upload_apk', methods=['POST'])
def upload_apk():
    if 'apk_file' not in request.files:
        flash('Файл не выбран', 'error')
        return redirect(url_for('index'))
    
    file = request.files['apk_file']
    if file.filename == '':
        flash('Файл не выбран', 'error')
        return redirect(url_for('index'))
    
    if file and file.filename.endswith('.apk'):
        filename = file.filename
        file.save(os.path.join('old_package', filename))
        flash(f'Файл {filename} успешно загружен!', 'success')
    else:
        flash('Загружайте только APK файлы', 'error')
    
    return redirect(url_for('index'))

@app.route('/change_packages', methods=['POST'])
def change_packages():
    selected_apk = request.form.get('selected_apk')
    
    if not selected_apk:
        flash('Выберите APK файл', 'error')
        return redirect(url_for('index'))
    
    if not os.path.exists('package_create/result.txt'):
        flash('Сначала сгенерируйте пакеты', 'error')
        return redirect(url_for('index'))
    
    try:
        subprocess.run(['cp', f'old_package/{selected_apk}', 'test.apk'])
        subprocess.run(['cp', 'package_create/result.txt', 'package_list.txt'])
        
        thread = threading.Thread(target=run_shell_command)
        thread.start()
        
        return jsonify({'status': 'started'})
    except Exception as e:
        return jsonify({'status': 'error', 'message': str(e)})

@app.route('/process_status')
def process_status():
    global process_output, process_running
    return jsonify({
        'running': process_running,
        'output': process_output
    })

@app.route('/download_results')
def download_results():
    if not os.path.exists('new_package') or not os.listdir('new_package'):
        flash('Нет файлов для скачивания', 'error')
        return redirect(url_for('index'))
    
    zip_filename = f'results_{datetime.now().strftime("%Y%m%d_%H%M%S")}.zip'
    zip_path = zip_filename
    
    with zipfile.ZipFile(zip_path, 'w') as zipf:
        for root, dirs, files in os.walk('new_package'):
            for file in files:
                file_path = os.path.join(root, file)
                zipf.write(file_path, os.path.relpath(file_path, 'new_package'))
    
    return send_file(zip_path, as_attachment=True, download_name=zip_filename)

@app.route('/history')
def history():
    history_data = load_history()
    return render_template('history.html', history=history_data)

@app.route('/update_from_github', methods=['POST'])
def update_from_github():
    try:
        result = subprocess.run(['bash', 'update.sh'], capture_output=True, text=True)
        
        if result.returncode == 0:
            flash('Обновление успешно! Перезапустите сервис.', 'success')
        else:
            flash(f'Ошибка обновления: {result.stderr}', 'error')
            
    except Exception as e:
        flash(f'Ошибка: {str(e)}', 'error')
    
    return redirect(url_for('index'))

def save_to_history(count):
    history_data = load_history()
    history_data.append({
        'count': count,
        'timestamp': datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    })
    save_history(history_data)

def load_history():
    history_file = 'history.json'
    if os.path.exists(history_file):
        try:
            with open(history_file, 'r', encoding='utf-8') as f:
                return json.load(f)
        except:
            return []
    return []

def save_history(data):
    with open('history.json', 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, indent=2)

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=False)
PYEOF

# Создаем генератор пакетов
cat > package_create/create_packeges.py << 'PYEOF'
import random
import string
import os

def generate_package():
    """Генерируем случайное имя пакета"""
    words1 = ['com', 'org', 'net', 'app', 'pro', 'dev']
    words2 = ['android', 'mobile', 'app', 'game', 'tool', 'util', 'social', 'media', 'photo', 'video']
    words3 = ['manager', 'viewer', 'editor', 'player', 'browser', 'scanner', 'tracker', 'helper', 'boost', 'cleaner']
    
    word1 = random.choice(words1)
    word2 = random.choice(words2)
    word3 = random.choice(words3)
    suffix = ''.join(random.choices(string.ascii_lowercase + string.digits, k=3))
    
    return f"{word1}.{word2}.{word3}{suffix}"

def load_used_packages(filename):
    if not os.path.exists(filename):
        return set()
    with open(filename, 'r') as f:
        return set(line.strip() for line in f)

def save_packages(packages, filename):
    with open(filename, 'a') as f:
        for pkg in packages:
            f.write(pkg + '\n')

def main():
    try:
        count = int(input("Сколько пакетов сгенерировать? "))
    except ValueError:
        print("Введите число!")
        return

    used = load_used_packages("used.txt")
    new_packages = set()

    while len(new_packages) < count:
        pkg = generate_package()
        if pkg not in used:
            new_packages.add(pkg)

    save_packages(new_packages, "result.txt")
    save_packages(new_packages, "used.txt")
    print(f"{len(new_packages)} уникальных пакетов записано в result.txt и used.txt")

if __name__ == "__main__":
    main()
PYEOF

# Создаем JS скрипт обработки
cat > change.js << 'JSEOF'
const fs = require('fs');
const path = require('path');
const readline = require('readline');
const { exec } = require('child_process');
require('dotenv').config();

function runCommand(command, workingDir = __dirname) {
    console.log(command);
    return new Promise((resolve) => {
        const options = {};
        if (workingDir) {
            options.cwd = workingDir;
        }

        exec(command, options, (error, stdout, stderr) => {
            if (error) {
                console.log(stdout);
                console.log(stderr);
                resolve(error.code);
            } else {
                console.log(stdout);
                resolve(0);
            }
        });
    });
}

async function getPackageAttribute(filePath) {
    try {
        const xmlData = await fs.promises.readFile(filePath, 'utf-8');
        const packageMatch = xmlData.match(/package="([^"]+)"/);
        if (packageMatch) {
            return packageMatch[1];
        } else {
            throw new Error('Атрибут "package" не найден в AndroidManifest.xml');
        }
    } catch (err) {
        throw new Error(`Ошибка при обработке XML: ${err.message}`);
    }
}

function createReplacements(oldPackage, newPackage) {
    const res = [];
    res.push({ search: oldPackage, replace: newPackage });
    res.push({ search: oldPackage.replaceAll('.', '/'), replace: newPackage.replaceAll('.', '/') });
    return res;
}

function processFile(filePath, replacements) {
    let content = fs.readFileSync(filePath, 'utf-8');
    let originalContent = content;

    for (const { search, replace } of replacements) {
        content = content.split(search).join(replace);
    }

    if (content !== originalContent) {
        fs.writeFileSync(filePath, content, 'utf-8');
        console.log(`Modified: ${filePath}`);
    }
}

function processDirectory(dir, replacements) {
    const entries = fs.readdirSync(dir, { withFileTypes: true });

    for (const entry of entries) {
        const fullPath = path.join(dir, entry.name);

        if (entry.isDirectory()) {
            processDirectory(fullPath, replacements);
        } else if (entry.isFile() && (fullPath.endsWith('.smali') || fullPath.endsWith('.xml'))) {
            processFile(fullPath, replacements);
        }
    }
}

async function filterLinesByRegex(filePath, regex) {
    const result = [];
    const fileStream = fs.createReadStream(filePath);
    const rl = readline.createInterface({
        input: fileStream,
        crlfDelay: Infinity
    });

    for await (const line of rl) {
        if (regex.test(line)) {
            result.push(line.trim());
        }
    }

    return result;
}

async function main(args) {
    const packageNameRegexp = /^(?:[a-zA-Z]+(?:\d*[a-zA-Z_]*)*)(?:\.[a-zA-Z]+(?:\d*[a-zA-Z_]*)*)+$/;
    const apkPath = args[0];
    const packageListPath = args[1];
    const decodedApkPath = `${apkPath}.decoded`;
    let workingDir = path.dirname(apkPath);

    const javaPath = process.env.JAVA_PATH || 'java';
    const zipalignPath = process.env.ZIPALIGN_PATH || 'zipalign';
    const apksignerPath = process.env.APKSIGNER_PATH || 'apksigner';
    const keystorePath = path.join(workingDir, process.env.KEYSTORE_NAME || 'keystore.jks');
    const keyAlias = process.env.KEY_ALIAS || 'mykey';
    const keystorePassword = process.env.KEYSTORE_PASSWORD || '123456';
    const keyPassword = process.env.KEY_PASSWORD || '123456';

    const packages = await filterLinesByRegex(packageListPath, packageNameRegexp);
    console.log('packages', packages);

    if (packages.length == 0) {
        console.log('Error, package list is empty');
        return;
    }

    let code = 0;
    code = await runCommand(`${javaPath} -jar /usr/local/bin/apktool.jar d -f -o ${decodedApkPath} ${apkPath}`, workingDir);
    console.log('decode code: ', code);

    for (let index = 0; index < packages.length; index++) {
        const newPackageName = packages[index];
        console.log('newPackageName', newPackageName);
        
        const newApkPath = path.join(workingDir, `${newPackageName}.apk`);
        const newAlignedApkPath = path.join(workingDir, `aligned_${newPackageName}.apk`);
        const newSignedApkPath = path.join(workingDir, `signed_${newPackageName}.apk`);

        let origPackageName = await getPackageAttribute(path.join(decodedApkPath, 'AndroidManifest.xml'));
        console.log('origPackageName: ', origPackageName);

        const replacements = createReplacements(origPackageName, newPackageName);
        processDirectory(decodedApkPath, replacements);

        code = await runCommand(`${javaPath} -jar /usr/local/bin/apktool.jar b -o ${newApkPath} ${decodedApkPath}`, workingDir);
        console.log('build code: ', code);

        code = await runCommand(`${zipalignPath} -v -p 4 ${newApkPath} ${newAlignedApkPath}`, workingDir);
        console.log('align code: ', code);

        code = await runCommand(`${apksignerPath} sign --ks ${keystorePath} --ks-key-alias ${keyAlias} --ks-pass pass:${keystorePassword} --key-pass pass:${keyPassword} --out ${newSignedApkPath} ${newAlignedApkPath}`, workingDir);
        console.log('sign code: ', code);
        
        if (code == 0) {
            if (fs.existsSync(newAlignedApkPath)) {
                fs.unlinkSync(newAlignedApkPath);
            }
            if (fs.existsSync(newApkPath)) {
                fs.unlinkSync(newApkPath);
            }
            if (fs.existsSync(`new_package/${newPackageName}.apk`)) {
                fs.unlinkSync(`new_package/${newPackageName}.apk`);
            }
            fs.renameSync(newSignedApkPath, `new_package/${newPackageName}.apk`);
        }
    }

    if (fs.existsSync(decodedApkPath)) {
        fs.rmSync(decodedApkPath, { recursive: true });
    }
    
    console.log('Done!');
}

main(process.argv.slice(2));
JSEOF

# Создаем базовые HTML шаблоны
mkdir -p templates

cat > templates/base.html << 'HTMLEOF'
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>APK Package Changer</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.1.3/dist/css/bootstrap.min.css" rel="stylesheet">
</head>
<body>
    <nav class="navbar navbar-expand-lg navbar-dark bg-dark">
        <div class="container">
            <a class="navbar-brand" href="/">APK Package Changer</a>
            <div class="navbar-nav">
                <a class="nav-link" href="/">Главная</a>
                <a class="nav-link" href="/history">История</a>
            </div>
        </div>
    </nav>

    <div class="container mt-4">
        {% with messages = get_flashed_messages(with_categories=true) %}
            {% if messages %}
                {% for category, message in messages %}
                    <div class="alert alert-{{ 'danger' if category == 'error' else 'success' }} alert-dismissible fade show" role="alert">
                        {{ message }}
                        <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
                    </div>
                {% endfor %}
            {% endif %}
        {% endwith %}

        {% block content %}{% endblock %}
    </div>

    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.1.3/dist/js/bootstrap.bundle.min.js"></script>
</body>
</html>
HTMLEOF

cat > templates/index.html << 'HTMLEOF'
{% extends "base.html" %}

{% block content %}
<div class="row">
    <div class="col-md-6">
        <h3>1. Сгенерировать пакеты</h3>
        <form method="POST" action="/generate_packages">
            <div class="mb-3">
                <label class="form-label">Количество пакетов</label>
                <input type="number" name="count" class="form-control" value="10" min="1" max="1000">
            </div>
            <button type="submit" class="btn btn-primary">Сгенерировать</button>
        </form>
    </div>
    
    <div class="col-md-6">
        <h3>2. Загрузить APK</h3>
        <form method="POST" action="/upload_apk" enctype="multipart/form-data">
            <div class="mb-3">
                <input type="file" name="apk_file" class="form-control" accept=".apk">
            </div>
            <button type="submit" class="btn btn-success">Загрузить</button>
        </form>
    </div>
</div>

<div class="row mt-4">
    <div class="col-md-12">
        <h3>3. Изменить пакеты</h3>
        {% if apk_files and result_exists %}
        <form method="POST" action="/change_packages">
            <div class="mb-3">
                <label class="form-label">Выберите APK файл</label>
                <select name="selected_apk" class="form-control">
                    {% for apk in apk_files %}
                    <option value="{{ apk }}">{{ apk }}</option>
                    {% endfor %}
                </select>
            </div>
            <button type="submit" class="btn btn-warning">Начать обработку</button>
        </form>
        {% else %}
        <p class="text-muted">Сначала загрузите APK файл и сгенерируйте пакеты</p>
        {% endif %}
    </div>
</div>

<div class="row mt-4">
    <div class="col-md-6">
        <a href="/download_results" class="btn btn-info">Скачать результаты</a>
    </div>
    <div class="col-md-6">
        <form method="POST" action="/update_from_github" style="display: inline;">
            <button type="submit" class="btn btn-secondary">Обновить с GitHub</button>
        </form>
    </div>
</div>
{% endblock %}
HTMLEOF

cat > templates/history.html << 'HTMLEOF'
{% extends "base.html" %}

{% block content %}
<h2>История генерации пакетов</h2>

<div class="table-responsive">
    <table class="table table-striped">
        <thead>
            <tr>
                <th>Дата</th>
                <th>Количество пакетов</th>
            </tr>
        </thead>
        <tbody>
            {% for item in history %}
            <tr>
                <td>{{ item.timestamp }}</td>
                <td>{{ item.count }}</td>
            </tr>
            {% endfor %}
        </tbody>
    </table>
</div>

<a href="/" class="btn btn-primary">Назад</a>
{% endblock %}
HTMLEOF

# Создаем requirements.txt
cat > requirements.txt << 'PYEOF'
Flask==3.0.0
python-dotenv==1.0.0
PYEOF

# Создаем package.json
cat > package.json << 'JSEOF'
{
  "name": "apk-package-changer",
  "version": "1.0.0",
  "description": "APK Package Changer",
  "main": "change.js",
  "dependencies": {
    "dotenv": "^16.0.0"
  }
}
JSEOF

# Создаем .env файл
cat > .env << 'ENVEOF'
JAVA_PATH=/usr/bin/java
ZIPALIGN_PATH=/opt/android-sdk/build-tools/34.0.0/zipalign
APKSIGNER_PATH=/opt/android-sdk/build-tools/34.0.0/apksigner
KEYSTORE_NAME=keystore.jks
KEY_ALIAS=mykey
KEYSTORE_PASSWORD=123456
KEY_PASSWORD=123456
ENVEOF

# Создаем скрипт запуска
cat > run.sh << 'RUNEOF'
#!/bin/bash
node change.js test.apk package_list.txt
RUNEOF

chmod +x run.sh

# Создаем keystore
echo "Создание keystore..."
if [ ! -f "keystore.jks" ]; then
    keytool -genkey -v -keystore keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias mykey \
        -dname "CN=APK Changer, OU=Dev, O=Company, L=City, S=State, C=US" \
        -storepass 123456 -keypass 123456 -noprompt
fi

# Создаем скрипт обновления
cat > update.sh << 'UPDATEEOF'
#!/bin/bash
echo "=== Обновление APK Package Changer ==="

# Остановка сервиса
sudo systemctl stop apk-changer

# Создание резервной копии пользовательских данных
cp -r old_package old_package.backup 2>/dev/null || true
cp -r new_package new_package.backup 2>/dev/null || true
cp -r package_create package_create.backup 2>/dev/null || true
cp .env .env.backup 2>/dev/null || true
cp keystore.jks keystore.jks.backup 2>/dev/null || true

# Здесь можно добавить git pull если у вас есть репозиторий
# git pull origin main

# Восстановление пользовательских данных
cp -r old_package.backup/* old_package/ 2>/dev/null || true
cp -r new_package.backup/* new_package/ 2>/dev/null || true
cp -r package_create.backup/* package_create/ 2>/dev/null || true
cp .env.backup .env 2>/dev/null || true
cp keystore.jks.backup keystore.jks 2>/dev/null || true

# Обновление зависимостей
pip3 install -r requirements.txt --upgrade
npm install

# Запуск сервиса
sudo systemctl start apk-changer

echo "Обновление завершено!"
UPDATEEOF

chmod +x update.sh

# Установка Python зависимостей
echo "Установка Python зависимостей..."
pip3 install -r requirements.txt

# Установка Node.js зависимостей
echo "Установка Node.js зависимостей..."
npm install

# Создание systemd сервиса
echo "Создание systemd сервиса..."
CURRENT_USER=$(whoami)
sudo tee /etc/systemd/system/apk-changer.service > /dev/null << EOF
[Unit]
Description=APK Package Changer Web Service
After=network.target

[Service]
Type=simple
User=$CURRENT_USER
WorkingDirectory=$PROJECT_DIR
Environment=PATH=/usr/bin:/usr/local/bin:$ANDROID_HOME/build-tools/$BUILD_TOOLS_VERSION:$ANDROID_HOME/platform-tools
Environment=ANDROID_HOME=$ANDROID_HOME
Environment=PYTHONPATH=$PROJECT_DIR
Environment=NODE_PATH=$PROJECT_DIR/node_modules
ExecStart=/usr/bin/python3 -u app.py
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# Настройка firewall
echo "Настройка firewall..."
sudo ufw allow 5000/tcp
sudo ufw reload 2>/dev/null || true

# Запуск и включение сервиса
echo "Запуск сервиса..."
sudo systemctl daemon-reload
sudo systemctl enable apk-changer
sudo systemctl start apk-changer

# Ожидание запуска
echo "Ожидание запуска сервиса..."
sleep 5

# Проверка статуса
echo "Проверка статуса сервиса..."
sudo systemctl status apk-changer --no-pager

echo ""
echo "=== Установка завершена ==="
echo "Проект установлен в: $PROJECT_DIR"
echo "Веб-панель доступна по адресу: http://$(hostname -I | awk '{print $1}'):5000"
echo ""
echo "Полезные команды:"
echo "  Статус сервиса: sudo systemctl status apk-changer"
echo "  Логи сервиса: sudo journalctl -u apk-changer -f"
echo "  Перезапуск: sudo systemctl restart apk-changer"
echo "  Остановка: sudo systemctl stop apk-changer"
echo ""
echo "Если сервис не запустился, проверьте логи и убедитесь что порт 5000 свободен"
