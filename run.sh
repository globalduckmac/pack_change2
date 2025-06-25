
#!/bin/bash

echo "=== Начало обработки APK ==="

# Проверяем наличие необходимых файлов
if [ ! -f "test.apk" ]; then
    echo "ОШИБКА: Файл test.apk не найден!"
    exit 1
fi

if [ ! -f "package_list.txt" ]; then
    echo "ОШИБКА: Файл package_list.txt не найден!"
    exit 1
fi

# Проверяем наличие apktool
if [ ! -f "apktool.jar" ]; then
    echo "Загружаем apktool..."
    wget -q https://bitbucket.org/iBotPeaches/apktool/downloads/apktool_2.9.3.jar -O apktool.jar
    if [ $? -ne 0 ]; then
        echo "ОШИБКА: Не удалось загрузить apktool!"
        exit 1
    fi
fi

# Создаем временную директорию
TEMP_DIR="temp_apk_processing"
rm -rf $TEMP_DIR
mkdir -p $TEMP_DIR

echo "Декомпилируем APK..."
java -jar apktool.jar d test.apk -o $TEMP_DIR/decompiled
if [ $? -ne 0 ]; then
    echo "ОШИБКА: Не удалось декомпилировать APK!"
    exit 1
fi

# Читаем список пакетов и обрабатываем каждый
counter=1
while IFS= read -r package_name; do
    if [ -z "$package_name" ]; then
        continue
    fi
    
    echo "Обрабатываем пакет $counter: $package_name"
    
    # Копируем декомпилированную версию
    cp -r $TEMP_DIR/decompiled $TEMP_DIR/processing_$counter
    
    # Меняем package name в AndroidManifest.xml
    manifest_file="$TEMP_DIR/processing_$counter/AndroidManifest.xml"
    if [ -f "$manifest_file" ]; then
        # Получаем оригинальное имя пакета
        original_package=$(grep -o 'package="[^"]*"' "$manifest_file" | cut -d'"' -f2)
        if [ ! -z "$original_package" ]; then
            echo "Меняем пакет с $original_package на $package_name"
            sed -i "s/package=\"$original_package\"/package=\"$package_name\"/g" "$manifest_file"
        fi
    fi
    
    # Компилируем обратно
    output_file="new_package/${package_name}.apk"
    echo "Компилируем APK: $output_file"
    
    java -jar apktool.jar b $TEMP_DIR/processing_$counter -o "$output_file"
    if [ $? -eq 0 ]; then
        echo "✅ Успешно создан: $output_file"
    else
        echo "❌ Ошибка при создании: $output_file"
    fi
    
    # Очищаем временные файлы для этого пакета
    rm -rf $TEMP_DIR/processing_$counter
    
    counter=$((counter + 1))
done < package_list.txt

# Очищаем временные файлы
rm -rf $TEMP_DIR

echo "=== Обработка завершена ==="
echo "Создано файлов в new_package:"
ls -la new_package/ | grep "\.apk$" | wc -l
