
import random
import nltk
from nltk.corpus import words
import os

# Скачиваем словарь (один раз)
try:
    nltk.download('words', quiet=True)
except:
    pass

def generate_package(wordlist):
    word1 = random.choice(wordlist)
    word2 = random.choice(wordlist)
    word3 = random.choice(wordlist)
    return f"{word1.lower()}.{word2.lower()}.{word3.lower()}"

def load_used_packages(filename):
    if not os.path.exists(filename):
        return set()
    with open(filename, 'r') as f:
        return set(line.strip() for line in f)

def save_packages(packages, filename, append=True):
    mode = 'a' if append else 'w'
    with open(filename, mode) as f:
        for pkg in packages:
            f.write(pkg + '\n')

def main():
    try:
        count = int(input("Сколько пакетов сгенерировать? "))
    except ValueError:
        print("Введите число!")
        return

    # Используем только слова длиной от 3 до 7 символов
    try:
        full_wordlist = [w for w in words.words() if 3 <= len(w) <= 7 and w.isalpha()]
    except:
        # Если NLTK не работает, используем базовые слова
        full_wordlist = ['app', 'test', 'demo', 'game', 'tool', 'util', 'main', 'core', 'base', 'data', 'file', 'view', 'work', 'user', 'info', 'help', 'menu', 'page', 'item', 'list', 'edit', 'save', 'load', 'play', 'stop', 'start', 'end', 'home', 'back', 'next', 'prev', 'new', 'old', 'big', 'small', 'fast', 'slow', 'good', 'bad', 'hot', 'cold', 'red', 'blue', 'green', 'white', 'black']
    
    used = load_used_packages("used.txt")
    new_packages = set()

    while len(new_packages) < count:
        pkg = generate_package(full_wordlist)
        if pkg not in used:
            new_packages.add(pkg)

    save_packages(new_packages, "result.txt", append=False)  # Перезаписываем result.txt
    save_packages(new_packages, "used.txt", append=True)      # Добавляем в used.txt
    print(f"{len(new_packages)} уникальных пакетов записано в result.txt и used.txt")

if __name__ == "__main__":
    main()
