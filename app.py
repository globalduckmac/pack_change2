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
current_operation = None

def run_shell_command():
    global process_output, process_running, current_operation
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

        # Сохраняем в историю после успешного завершения
        if current_operation and process.returncode == 0:
            save_apk_operation_to_history(current_operation)
            current_operation = None

        # Очищаем result.txt после обработки, чтобы использовались только новые пакеты
        result_file = os.path.join('package_create', 'result.txt')
        if os.path.exists(result_file):
            open(result_file, 'w').close()  # Очищаем файл
            process_output.append("Список пакетов очищен - готов к новой генерации")

    except Exception as e:
        process_output.append(f"Ошибка: {str(e)}")
    finally:
        process_running = False

@app.route('/')
def index():
    # Используем относительные пути от текущей рабочей директории
    current_dir = os.getcwd()

    # Получаем список APK файлов в old_package
    apk_files = []
    apk_file_sizes = {}
    old_package_dir = 'old_package'
    if os.path.exists(old_package_dir):
        apk_files = [f for f in os.listdir(old_package_dir) if f.endswith('.apk')]
        # Получаем размеры файлов
        for apk_file in apk_files:
            try:
                file_path = os.path.join(old_package_dir, apk_file)
                size_bytes = os.path.getsize(file_path)
                size_mb = round(size_bytes / (1024 * 1024), 2)
                apk_file_sizes[apk_file] = size_mb
            except:
                apk_file_sizes[apk_file] = 0

    # Получаем список готовых APK файлов в new_package
    new_apk_files = []
    new_apk_file_sizes = {}
    new_package_dir = 'new_package'
    if os.path.exists(new_package_dir):
        new_apk_files = [f for f in os.listdir(new_package_dir) if f.endswith('.apk')]
        # Получаем размеры новых файлов
        for apk_file in new_apk_files:
            try:
                file_path = os.path.join(new_package_dir, apk_file)
                size_bytes = os.path.getsize(file_path)
                size_mb = round(size_bytes / (1024 * 1024), 2)
                new_apk_file_sizes[apk_file] = size_mb
            except:
                new_apk_file_sizes[apk_file] = 0

    # Проверяем наличие сгенерированных пакетов
    result_file = os.path.join('package_create', 'result.txt')
    used_file = os.path.join('package_create', 'used.txt')
    result_exists = os.path.exists(result_file)
    used_exists = os.path.exists(used_file)

    # Читаем сгенерированные пакеты для отображения
    generated_packages = []
    if result_exists:
        try:
            with open(result_file, 'r', encoding='utf-8') as f:
                generated_packages = [line.strip() for line in f.readlines() if line.strip()]
        except Exception as e:
            print(f"Ошибка чтения result.txt: {e}")

    # Читаем уже использованные пакеты
    used_packages = []
    if used_exists:
        try:
            with open(used_file, 'r', encoding='utf-8') as f:
                used_packages = [line.strip() for line in f.readlines() if line.strip()]
        except Exception as e:
            print(f"Ошибка чтения used.txt: {e}")

    print(f"=== ОТЛАДКА ОТОБРАЖЕНИЯ ===")
    print(f"result_exists: {result_exists}")
    print(f"Количество generated_packages: {len(generated_packages)}")
    print(f"Количество used_packages: {len(used_packages)}")

    return render_template('index.html', 
                         apk_files=apk_files, 
                         new_apk_files=new_apk_files,
                         result_exists=result_exists,
                         used_exists=used_exists,
                         generated_packages=generated_packages,
                         used_packages=used_packages,
                         apk_file_sizes=apk_file_sizes,
                         new_apk_file_sizes=new_apk_file_sizes)

@app.route('/generate_packages', methods=['POST'])
def generate_packages():
    try:
        count = int(request.form.get('count', 10))

        # Очищаем result.txt перед генерацией новых пакетов
        result_file = os.path.join('package_create', 'result.txt')
        if os.path.exists(result_file):
            open(result_file, 'w').close()  # Очищаем файл
            print("result.txt очищен перед новой генерацией")

        # Проверяем существование скрипта
        script_path = os.path.join('package_create', 'create_packeges.py')
        package_create_dir = 'package_create'

        print(f"=== ОТЛАДКА ГЕНЕРАЦИИ ===")
        print(f"Текущая рабочая директория: {os.getcwd()}")
        print(f"Путь к скрипту: {script_path}")
        print(f"Файл существует: {os.path.exists(script_path)}")
        print(f"Рабочая директория для скрипта: {package_create_dir}")

        if not os.path.exists(script_path):
            flash(f'Файл скрипта не найден: {script_path}', 'error')
            return redirect(url_for('index'))

        # Запускаем скрипт из папки package_create
        result = subprocess.run(['python3', 'create_packeges.py'], 
                              input=str(count), 
                              text=True, 
                              capture_output=True,
                              cwd=package_create_dir)

        print(f"Результат выполнения скрипта:")
        print(f"Return code: {result.returncode}")
        print(f"Stdout: {result.stdout}")
        print(f"Stderr: {result.stderr}")

        if result.returncode == 0:
            # Проверяем, что файлы действительно созданы
            result_file = os.path.join(package_create_dir, 'result.txt')
            if os.path.exists(result_file):
                # Читаем созданные пакеты для подтверждения
                with open(result_file, 'r', encoding='utf-8') as f:
                    created_packages = [line.strip() for line in f.readlines() if line.strip()]
                
                print(f"Создано пакетов: {len(created_packages)}")
                print(f"Первые 5 пакетов: {created_packages[:5]}")
                
                # Сохраняем в историю с дополнительной информацией
                save_to_history(count, created_packages[:5])  # Сохраняем первые 5 пакетов как пример
                flash(f'Успешно сгенерировано {len(created_packages)} пакетов!', 'success')
            else:
                flash('Файл result.txt не был создан', 'error')
        else:
            flash(f'Ошибка при генерации: {result.stderr}', 'error')
    except Exception as e:
        flash(f'Ошибка: {str(e)}', 'error')
        print(f"Исключение: {e}")

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

    # Используем относительные пути
    result_file = os.path.join('package_create', 'result.txt')
    if not os.path.exists(result_file):
        return jsonify({'status': 'error', 'message': 'Сначала сгенерируйте пакеты'})

    # Создаем символические ссылки для скрипта
    try:
        # Копируем выбранный APK как test.apk
        source_apk = os.path.join('old_package', selected_apk)
        target_apk = 'test.apk'
        subprocess.run(['cp', source_apk, target_apk])
        
        # Копируем result.txt как package_list.txt
        target_packages = 'package_list.txt'
        subprocess.run(['cp', result_file, target_packages])

        # Сохраняем информацию о текущей операции для истории
        result_packages = []
        with open(result_file, 'r', encoding='utf-8') as f:
            result_packages = [line.strip() for line in f.readlines() if line.strip()]
        
        # Сохраняем в глобальную переменную для использования после завершения процесса
        global current_operation
        current_operation = {
            'apk_name': selected_apk,
            'packages_count': len(result_packages),
            'packages': result_packages[:5]  # Первые 5 для примера
        }

        print(f"=== ОТЛАДКА СМЕНЫ ПАКЕТОВ ===")
        print(f"Выбранный APK: {selected_apk}")
        print(f"Исходный файл: {source_apk}, существует: {os.path.exists(source_apk)}")
        print(f"Целевой APK: {target_apk}, создан: {os.path.exists(target_apk)}")
        print(f"Список пакетов: {target_packages}, создан: {os.path.exists(target_packages)}")
        print(f"Количество пакетов для обработки: {len(result_packages)}")

        # Запускаем процесс в отдельном потоке
        thread = threading.Thread(target=run_shell_command)
        thread.start()

        return jsonify({'status': 'started'})
    except Exception as e:
        print(f"Ошибка в change_packages: {e}")
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

def save_to_history(count, package_examples=None):
    history_data = load_history()
    entry = {
        'date': datetime.now().isoformat(),
        'count': count,
        'timestamp': datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        'type': 'generation'
    }
    if package_examples:
        entry['examples'] = package_examples
    history_data.append(entry)
    save_history(history_data)

def save_apk_operation_to_history(operation):
    history_data = load_history()
    entry = {
        'date': datetime.now().isoformat(),
        'timestamp': datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        'type': 'apk_processing',
        'apk_name': operation['apk_name'],
        'packages_count': operation['packages_count'],
        'packages_examples': operation['packages']
    }
    history_data.append(entry)
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

@app.route('/clear_all_packages', methods=['POST'])
def clear_all_packages():
    try:
        # Очищаем все директории с пакетами
        directories = ['new_package', 'old_package']
        for directory in directories:
            if os.path.exists(directory):
                for file in os.listdir(directory):
                    file_path = os.path.join(directory, file)
                    if os.path.isfile(file_path):
                        os.unlink(file_path)
        
        # Очищаем файлы с пакетами
        package_files = [
            os.path.join('package_create', 'result.txt'),
            os.path.join('package_create', 'used.txt'),
            'package_list.txt',
            'test.apk'
        ]
        for file_path in package_files:
            if os.path.exists(file_path):
                os.unlink(file_path)
        
        flash('Все пакеты и файлы успешно удалены!', 'success')
        return jsonify({'status': 'success', 'message': 'Все пакеты удалены'})
    except Exception as e:
        return jsonify({'status': 'error', 'message': str(e)})

@app.route('/download_packages_by_apk/<apk_name>')
def download_packages_by_apk(apk_name):
    try:
        # Получаем историю операций с этим APK
        history_data = load_history()
        apk_operations = [h for h in history_data if h.get('type') == 'apk_processing' and h.get('apk_name') == apk_name]
        
        if not apk_operations:
            flash(f'Не найдено операций для APK: {apk_name}', 'error')
            return redirect(url_for('history'))
        
        # Создаем архив с APK файлами, созданными из этого исходного APK
        zip_filename = f'packages_from_{apk_name}_{datetime.now().strftime("%Y%m%d_%H%M%S")}.zip'
        zip_path = zip_filename
        
        files_added = 0
        with zipfile.ZipFile(zip_path, 'w') as zipf:
            if os.path.exists('new_package'):
                for file in os.listdir('new_package'):
                    if file.endswith('.apk'):
                        file_path = os.path.join('new_package', file)
                        zipf.write(file_path, file)
                        files_added += 1
        
        if files_added == 0:
            flash('Нет файлов для архивации', 'error')
            return redirect(url_for('history'))
        
        return send_file(zip_path, as_attachment=True, download_name=zip_filename)
    except Exception as e:
        flash(f'Ошибка создания архива: {str(e)}', 'error')
        return redirect(url_for('history'))

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