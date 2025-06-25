
# Инструкция по развертыванию

## Развертывание с GitHub репозитория

1. **Перед запуском скрипта установите URL вашего репозитория:**

```bash
export GITHUB_REPO_URL=https://github.com/YOUR_USERNAME/apk-package-changer.git
```

Замените `YOUR_USERNAME` на ваш GitHub username.

2. **Запустите скрипт развертывания:**

```bash
chmod +x deploy.sh
./deploy.sh
```

## Альтернативный способ (ручное клонирование)

1. **Клонируйте репозиторий:**

```bash
git clone https://github.com/YOUR_USERNAME/apk-package-changer.git
cd apk-package-changer
```

2. **Запустите упрощенную установку:**

```bash
# Установка зависимостей
sudo apt update
sudo apt install -y python3 python3-pip python3-venv nodejs npm openjdk-17-jdk

# Создание виртуального окружения
python3 -m venv venv
source venv/bin/activate

# Установка Python зависимостей
pip install -r requirements.txt

# Установка Node.js зависимостей
npm install

# Запуск приложения
python app.py
```

## Проверка корректности установки

После развертывания проверьте, что все файлы шаблонов скопированы:

```bash
ls -la templates/
# Должны быть файлы: base.html, index.html, history.html
```

Если файлы шаблонов неполные, скопируйте их вручную из репозитория.
