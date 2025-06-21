import random
import nltk
from nltk.corpus import words
import os

# Скачиваем словарь (один раз)
nltk.download('words')

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

    # Используем только слова длиной от 3 до 7 символов
    full_wordlist = [w for w in words.words() if 3 <= len(w) <= 7 and w.isalpha()]
    used = load_used_packages("used.txt")
    new_packages = set()

    while len(new_packages) < count:
        pkg = generate_package(full_wordlist)
        if pkg not in used:
            new_packages.add(pkg)

    save_packages(new_packages, "result.txt")
    save_packages(new_packages, "used.txt")
    print(f"{len(new_packages)} уникальных пакетов записано в result.txt и used.txt")

if __name__ == "__main__":
    main()
