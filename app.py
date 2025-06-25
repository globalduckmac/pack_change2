# The issue was due to missing `apk_file_sizes` in the template context; corrected code ensures it's properly initialized and passed.
from flask import Flask, render_template, request, jsonify, send_file, redirect, url_for, flash
import os
import subprocess
import zipfile
import json
from datetime import datetime
import threading
import time

app = Flask(__name__)
app.secret_key = 'your-secret-key-here'

# Создаем необходимые папки
os.makedirs('old_package', exist_ok=True)
os.makedirs('new_package', exist_ok=True)
os.makedirs('package_create', exist_ok=True)

# Проверяем права доступа к папкам
try:
    # Проверяем, что можем записывать в папки
    test_dirs = ['old_package', 'new_package', 'package_create']
    for test_dir in test_dirs:
        if not os.access(test_dir, os.W_OK):
            print(f"ПРЕДУПРЕЖДЕНИЕ: Нет прав записи в папку {test_dir}")
except Exception as e:
    print(f"Ошибка при проверке папок: {e}")

# Глобальная переменная для процесса
process_output = []
process_running = False

def run_shell_command():
    global process_output, process_running
    process_output = []
    process_running = True

    try:
        # Запускаем run.sh
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
    # Получаем список APK файлов в old_package
    apk_files = []
    apk_file_sizes = {}
    if os.path.exists('old_package'):
        apk_files = [f for f in os.listdir('old_package') if f.endswith('.apk')]
        # Получаем размеры файлов
        for apk_file in apk_files:
            try:
                file_path = os.path.join('old_package', apk_file)
                size_bytes = os.path.getsize(file_path)
                size_mb = round(size_bytes / (1024 * 1024), 2)
                apk_file_sizes[apk_file] = size_mb
            except:
                apk_file_sizes[apk_file] = 0

    # Получаем список готовых APK файлов в new_package
    new_apk_files = []
    new_apk_file_sizes = {}
    if os.path.exists('new_package'):
        new_apk_files = [f for f in os.listdir('new_package') if f.endswith('.apk')]
        # Получаем размеры новых файлов
        for apk_file in new_apk_files:
            try:
                file_path = os.path.join('new_package', apk_file)
                size_bytes = os.path.getsize(file_path)
                size_mb = round(size_bytes / (1024 * 1024), 2)
                new_apk_file_sizes[apk_file] = size_mb
            except:
                new_apk_file_sizes[apk_file] = 0

    # Проверяем наличие сгенерированных пакетов
    result_exists = os.path.exists('package_create/result.txt')
    used_exists = os.path.exists('package_create/used.txt')

    # Читаем сгенерированные пакеты для отображения
    generated_packages = []
    if result_exists:
        try:
            with open('package_create/result.txt', 'r') as f:
                generated_packages = [line.strip() for line in f.readlines() if line.strip()]
        except:
            pass

    return render_template('index.html', 
                         apk_files=apk_files, 
                         new_apk_files=new_apk_files,
                         result_exists=result_exists,
                         used_exists=used_exists,
                         generated_packages=generated_packages,
                         apk_file_sizes=apk_file_sizes,
                         new_apk_file_sizes=new_apk_file_sizes)

@app.route('/generate_packages', methods=['POST'])
def generate_packages():
    try:
        count = int(request.form.get('count', 10))

        # Запускаем скрипт генерации пакетов
        script_path = 'package_create/create_packeges.py'
        current_dir = os.getcwd()
        full_script_path = os.path.join(current_dir, script_path)
        
        print(f"Текущая директория: {current_dir}")
        print(f"Ищем файл: {full_script_path}")
        print(f"Файл существует: {os.path.exists(full_script_path)}")
        
        if not os.path.exists(script_path):
            flash(f'Файл скрипта не найден: {script_path} в директории {current_dir}', 'error')
            return redirect(url_for('index'))

        result = subprocess.run(['python3', script_path], 
                              input=str(count), 
                              text=True, 
                              capture_output=True,
                              cwd=os.getcwd())

        if result.returncode == 0:
            # Сохраняем в историю
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
        
        # Создаем папку old_package если она не существует
        os.makedirs('old_package', exist_ok=True)
        
        filepath = os.path.join('old_package', filename)
        try:
            file.save(filepath)
            # Проверяем, что файл действительно сохранился
            if os.path.exists(filepath):
                flash(f'Файл {filename} успешно загружен!', 'success')
            else:
                flash(f'Ошибка сохранения файла {filename}', 'error')
        except Exception as e:
            flash(f'Ошибка при сохранении файла: {str(e)}', 'error')
    else:
        flash('Загружайте только APK файлы', 'error')

    return redirect(url_for('index'))

@app.route('/change_packages', methods=['POST'])
def change_packages():
    data = request.get_json()
    selected_apk = data.get('selected_apk') if data else request.form.get('selected_apk')

    if not selected_apk:
        return jsonify({'status': 'error', 'message': 'Выберите APK файл'})

    if not os.path.exists('package_create/result.txt'):
        return jsonify({'status': 'error', 'message': 'Сначала сгенерируйте пакеты'})

    # Создаем символические ссылки для скрипта
    try:
        # Копируем выбранный APK как test.apk
        subprocess.run(['cp', f'old_package/{selected_apk}', 'test.apk'])
        # Копируем result.txt как package_list.txt
        subprocess.run(['cp', 'package_create/result.txt', 'package_list.txt'])

        # Запускаем процесс в отдельном потоке
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

    # Создаем ZIP архив
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

@app.route('/delete_package_history/<int:index>')
def delete_package_history(index):
    history_data = load_history()
    if 0 <= index < len(history_data):
        history_data.pop(index)
        save_history(history_data)
        flash('Запись удалена из истории', 'success')
    return redirect(url_for('history'))

def save_to_history(count):
    history_data = load_history()
    history_data.append({
        'date': datetime.now().isoformat(),
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

@app.route('/update_from_github', methods=['POST'])
def update_from_github():
    try:
        # Остановка текущих процессов
        global process_running
        process_running = False

        # Обновление из GitHub
        result = subprocess.run(['git', 'pull', 'origin', 'main'], 
                              capture_output=True, text=True)

        if result.returncode == 0:
            # Установка новых зависимостей если нужно
            subprocess.run(['pip3', 'install', '-r', 'requirements.txt'], 
                          capture_output=True)
            subprocess.run(['npm', 'install'], capture_output=True)

            flash('Обновление успешно загружено! Сервер перезагружается...', 'success')

            # Перезапуск сервера через системный сервис
            def restart_server():
                time.sleep(2)
                subprocess.run(['sudo', 'systemctl', 'restart', 'apk-changer'])

            thread = threading.Thread(target=restart_server)
            thread.start()

            return jsonify({'status': 'success', 'message': 'Обновление завершено'})
        else:
            return jsonify({'status': 'error', 'message': f'Ошибка обновления: {result.stderr}'})
    except Exception as e:
        return jsonify({'status': 'error', 'message': str(e)})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=True)