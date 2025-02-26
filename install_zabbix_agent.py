import os
import requests
import zipfile
import shutil
import subprocess
import json
import configparser

# --- [Настройки] ---
ZABBIX_SERVER = "78.37.67.154"
ZABBIX_PORT = "8081"
ZABBIX_USER = "Admin"
ZABBIX_PASS = "zabbix"
TEMPLATE_ID = "10351"

ARCHIVE_URL = "https://cdn.zabbix.com/zabbix/binaries/stable/7.2/7.2.4/zabbix_agent-7.2.4-windows-amd64.zip"
ARCHIVE_FILE = os.path.join(os.environ["TEMP"], "zabbix_agent-7.2.4-windows-amd64.zip")
EXTRACT_DIR = os.path.join(os.environ["TEMP"], "zabbix_agent_extracted")
INSTALL_DIR = r"C:\Program Files\Zabbix_Agent2"

SETTINGS_FILE_1 = r"C:\Users\Kassa\AppData\Local\Programs\NevisVNClient\settings.ini"
SETTINGS_FILE_2 = r"C:\Users\Zav\AppData\Local\Programs\NevisVNClient\settings.ini"
CONFIG_FILE = os.path.join(INSTALL_DIR, "zabbix_agentd.conf")

# --- [Функции] ---
def download_file(url, destination):
    """Скачивает файл по URL."""
    print(f"Скачивание {url}...")
    try:
        response = requests.get(url, stream=True)
        response.raise_for_status()
        with open(destination, "wb") as file:
            for chunk in response.iter_content(chunk_size=8192):
                file.write(chunk)
        print(f"Файл успешно скачан: {destination}")
    except Exception as e:
        print(f"Ошибка при скачивании файла: {e}")
        exit(1)

def extract_zip(zip_file, extract_to):
    """Распаковывает ZIP-архив."""
    print(f"Распаковка {zip_file}...")
    try:
        with zipfile.ZipFile(zip_file, "r") as zip_ref:
            zip_ref.extractall(extract_to)
        print(f"Файлы успешно распакованы в: {extract_to}")
    except Exception as e:
        print(f"Ошибка при распаковке архива: {e}")
        exit(1)

def parse_settings(file_path):
    """Парсит файл settings.ini."""
    print(f"Парсинг файла {file_path}...")
    config = configparser.ConfigParser()
    try:
        config.read(file_path)
        settings = {
            "pharmacy_or_subgroup": config.get("App", "pharmacy_or_subgroup", fallback="").strip(),
            "device_or_name": config.get("App", "device_or_name", fallback="").strip(),
        }
        return settings
    except Exception as e:
        print(f"Ошибка при чтении файла settings.ini: {e}")
        exit(1)

def zabbix_api_request(method, params, auth_token=None):
    """Выполняет запрос к Zabbix API."""
    url = f"http://{ZABBIX_SERVER}:{ZABBIX_PORT}/api_jsonrpc.php"
    headers = {"Content-Type": "application/json"}
    payload = {
        "jsonrpc": "2.0",
        "method": method,
        "params": params,
        "id": 1,
    }
    if auth_token:
        payload["auth"] = auth_token

    try:
        response = requests.post(url, headers=headers, data=json.dumps(payload))
        response.raise_for_status()
        return response.json()
    except Exception as e:
        print(f"Ошибка при выполнении запроса к Zabbix API: {e}")
        exit(1)

# --- [Основной скрипт] ---
if __name__ == "__main__":
    # Парсинг settings.ini (вне зависимости от установки)
    settings_file = SETTINGS_FILE_1 if os.path.exists(SETTINGS_FILE_1) else SETTINGS_FILE_2
    settings = parse_settings(settings_file)

    # Определение Hostname (вне зависимости от установки)
    device_name = {
        "0": "CompZav",
        "1": "Kassa1",
        "2": "Kassa2",
        "3": "Kassa3",
        "4": "Kassa4",
        "102": "CompZav2",
        "99": "Server",
    }.get(settings.get("device_or_name", ""), "Unknown")

    pharmacy_or_subgroup = settings.get("pharmacy_or_subgroup", "").strip()
    hostname = f"Apteka{pharmacy_or_subgroup}_{device_name}"
    print(f"Hostname: {hostname}")

    # Проверка, запущен ли Zabbix Agent
    print("Проверка, запущен ли Zabbix Agent...")
    try:
        subprocess.run(["sc", "query", "Zabbix Agent"], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        print("Zabbix Agent уже установлен и запущен. Пропускаем установку.")
    except subprocess.CalledProcessError:
        print("Zabbix Agent не запущен. Начинаем установку...")

        # Скачивание архива Zabbix Agent
        download_file(ARCHIVE_URL, ARCHIVE_FILE)

        # Распаковка архива
        if os.path.exists(EXTRACT_DIR):
            shutil.rmtree(EXTRACT_DIR)
        os.makedirs(EXTRACT_DIR)
        extract_zip(ARCHIVE_FILE, EXTRACT_DIR)

        # Перемещение файлов
        print("Установка файлов Zabbix Agent...")
        if not os.path.exists(INSTALL_DIR):
            os.makedirs(INSTALL_DIR)
        shutil.copy(os.path.join(EXTRACT_DIR, "bin", "zabbix_agentd.exe"), INSTALL_DIR)
        shutil.copy(os.path.join(EXTRACT_DIR, "conf", "zabbix_agentd.conf"), INSTALL_DIR)

        # Настройка конфигурационного файла
        print("Настройка конфигурационного файла Zabbix Agent 2...")
        with open(CONFIG_FILE, "w") as config:
            config.write(f"Server={ZABBIX_SERVER}\n")
            config.write(f"ServerActive={ZABBIX_SERVER}\n")
            config.write(f"Hostname={hostname}\n")
            config.write(f"LogFile={os.path.join(INSTALL_DIR, 'zabbix_agentd.log')}\n")
            config.write("LogFileSize=1\n")
            config.write("DebugLevel=3\n")

        # Установка службы
        print("Установка службы Zabbix Agent 2...")
        subprocess.run([os.path.join(INSTALL_DIR, "zabbix_agentd.exe"), "-c", CONFIG_FILE, "-i"], check=True)

        # Запуск службы
        print("Запуск службы Zabbix Agent 2...")
        subprocess.run(["net", "start", "Zabbix Agent"], check=True)

    # Регистрация хоста в Zabbix
    print("Регистрация хоста на сервере Zabbix...")

    # Получение токена
    auth_response = zabbix_api_request("user.login", {"username": ZABBIX_USER, "password": ZABBIX_PASS})
    auth_token = auth_response.get("result")
    if not auth_token:
        print("Ошибка получения токена!")
        print("Ответ сервера:", auth_response)
        exit(1)

    # Определение groupid
    groupid = {
        "CompZav": "24",
        "CompZav2": "24",
        "Kassa1": "23",
        "Kassa2": "23",
        "Kassa3": "23",
        "Kassa4": "23",
        "Server": "25",
    }.get(device_name, "Unknown")

    # Регистрация хоста
    host_response = zabbix_api_request(
        "host.create",
        {
            "host": hostname,
            "groups": [{"groupid": groupid}],
            "templates": [{"templateid": TEMPLATE_ID}],
        },
        auth_token,
    )
            # "interfaces": [{"type": 1, "main": 1, "useip": 0, "dns": hostname, "port": "10050"}],
            
    if "error" in host_response:
        print("Ошибка при регистрации хоста!")
        print("Ответ сервера:", host_response)
        exit(1)

    print("Хост успешно зарегистрирован на сервере Zabbix!")
    print("Установка и настройка Zabbix Agent 2 завершена!")
