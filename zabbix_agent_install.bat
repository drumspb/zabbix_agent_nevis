@echo off
chcp 1251 >nul 2>&1
setlocal enabledelayedexpansion

REM --- [Настройки] ---
set ZABBIX_SERVER=78.37.67.154
set ZABBIX_PORT=8081
set ZABBIX_USER=Admin
set ZABBIX_PASS=UCu5ALMdAAgZEcD
set TEMPLATE_ID=10351

REM Указываем URL для скачивания Zabbix Agent
set ARCHIVE_URL=https://cdn.zabbix.com/zabbix/binaries/stable/7.2/7.2.4/zabbix_agent-7.2.4-windows-amd64.zip
set ARCHIVE_FILE=%TEMP%\zabbix_agent-7.2.4-windows-amd64.zip
set EXTRACT_DIR=%TEMP%\zabbix_agent_extracted
set INSTALL_DIR=C:\Program Files\Zabbix_Agent2

REM Указываем возможные пути к файлу settings.ini
set SETTINGS_FILE_1=C:\Users\Kassa\AppData\Local\Programs\NevisVNClient\settings.ini
set SETTINGS_FILE_2=C:\Users\Zav\AppData\Local\Programs\NevisVNClient\settings.ini
set CONFIG_FILE=%INSTALL_DIR%\zabbix_agentd.conf

REM Скачивание архива Zabbix Agent
echo Скачивание Zabbix Agent...
powershell -ExecutionPolicy Bypass -NoProfile -Command "try { Invoke-WebRequest -Uri '%ARCHIVE_URL%' -OutFile '%ARCHIVE_FILE%' } catch { exit 1 }"
if not exist "%ARCHIVE_FILE%" (
    echo Ошибка: Не удалось скачать архив Zabbix Agent.
    pause
    exit /b 1
)

REM Очистка предыдущих данных
echo Распаковка Zabbix Agent...
if exist "%EXTRACT_DIR%" rmdir /s /q "%EXTRACT_DIR%"
mkdir "%EXTRACT_DIR%"

REM Распаковка
"C:\Program Files\7-Zip\7z.exe" x "%ARCHIVE_FILE%" -o"%EXTRACT_DIR%" -y
if %ERRORLEVEL% neq 0 (
    echo Ошибка: Не удалось распаковать архив.
    pause
    exit /b 1
)

if not exist "%EXTRACT_DIR%\bin\zabbix_agentd.exe" (
    echo Ошибка: Файл zabbix_agentd.exe не найден после распаковки.
    pause
    exit /b 1
)

REM Перемещаем бинарники и конфигурационные файлы
echo Установка файлов Zabbix Agent...
mkdir "%INSTALL_DIR%" 2>nul
xcopy "%EXTRACT_DIR%\bin\zabbix_agentd.exe" "%INSTALL_DIR%\" /E /I /Y
xcopy "%EXTRACT_DIR%\conf\zabbix_agentd.conf" "%INSTALL_DIR%\" /E /I /Y

REM Проверяем наличие файла settings.ini
if exist "%SETTINGS_FILE_1%" (
    set SETTINGS_FILE=%SETTINGS_FILE_1%
) else if exist "%SETTINGS_FILE_2%" (
    set SETTINGS_FILE=%SETTINGS_FILE_2%
) else (
    echo Ошибка: Файл settings.ini не найден.
    pause
    exit /b 1
)

REM Парсим значения из settings.ini
echo Парсинг файла settings.ini...
for /f "tokens=2 delims==" %%a in ('findstr "pharmacy_or_subgroup" "%SETTINGS_FILE%"') do (
    set PHARMACY_OR_SUBGROUP=%%a
    REM Удаляем лишние пробелы
    set PHARMACY_OR_SUBGROUP=!PHARMACY_OR_SUBGROUP: =!
)
for /f "tokens=2 delims==" %%a in ('findstr "device_or_name" "%SETTINGS_FILE%"') do (
    set DEVICE_OR_NAME=%%a
    REM Удаляем лишние пробелы
    set DEVICE_OR_NAME=!DEVICE_OR_NAME: =!
)

REM Определяем значение для Hostname на основе device_or_name
if "%DEVICE_OR_NAME%"=="0" set DEVICE_NAME=CompZav
if "%DEVICE_OR_NAME%"=="1" set DEVICE_NAME=Kassa1
if "%DEVICE_OR_NAME%"=="2" set DEVICE_NAME=Kassa2
if "%DEVICE_OR_NAME%"=="3" set DEVICE_NAME=Kassa3
if "%DEVICE_OR_NAME%"=="4" set DEVICE_NAME=Kassa4
if "%DEVICE_OR_NAME%"=="102" set DEVICE_NAME=CompZav2
if "%DEVICE_OR_NAME%"=="99" set DEVICE_NAME=Server

REM Выводим значения для отладки
echo device_or_name: %DEVICE_OR_NAME%
echo pharmacy_or_subgroup: %PHARMACY_OR_SUBGROUP%

REM Устанавливаем Hostname
set HOSTNAME=Apteka%PHARMACY_OR_SUBGROUP%_%DEVICE_NAME%
echo Hostname: %HOSTNAME%

REM Настраиваем конфигурационный файл Zabbix Agent 2
echo Настройка конфигурационного файла Zabbix Agent 2...
(
    echo Server=78.37.67.154
    echo ServerActive=78.37.67.154
    echo Hostname=%HOSTNAME%
    echo LogFile=%INSTALL_DIR%\zabbix_agentd.log
    echo LogFileSize=1
    echo DebugLevel=3
) > "%CONFIG_FILE%"

REM Устанавливаем службу Zabbix Agent 2
echo Установка службы Zabbix Agent 2...
cd "%INSTALL_DIR%"
zabbix_agentd.exe -c zabbix_agentd.conf -i

REM Проверяем, успешно ли установлена служба
sc query "Zabbix Agent" >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo Ошибка: Служба Zabbix Agent не установлена.
    pause
    exit /b 1
)

REM Запускаем службу
echo Запуск службы Zabbix Agent 2...
net start "Zabbix Agent"
if %ERRORLEVEL% neq 0 (
    echo Ошибка: Не удалось запустить службу Zabbix Agent.
    echo Проверьте лог-файл: %INSTALL_DIR%\zabbix_agentd.log
    pause
    exit /b 1
)

REM --- [Определение groupid] ---
if "%DEVICE_NAME%"=="CompZav" set GROUPID=24
if "%DEVICE_NAME%"=="CompZav2" set GROUPID=24
if "%DEVICE_NAME%"=="Kassa1" set GROUPID=23
if "%DEVICE_NAME%"=="Kassa2" set GROUPID=23
if "%DEVICE_NAME%"=="Kassa3" set GROUPID=23
if "%DEVICE_NAME%"=="Kassa4" set GROUPID=23
if "%DEVICE_NAME%"=="Server" set GROUPID=25

REM --- [Получение токена] ---
echo Получение токена аутентификации...
set AUTH_JSON={"jsonrpc":"2.0","method":"user.login","params":{"user":"%ZABBIX_USER%","password":"%ZABBIX_PASS%"},"id":1}

for /f "delims=" %%a in ('powershell -Command "$response = Invoke-WebRequest -Uri 'http://%ZABBIX_SERVER%:%ZABBIX_PORT%/api_jsonrpc.php' -Method Post -Body '%AUTH_JSON%' -ContentType 'application/json'; $response.Content | ConvertFrom-Json | Select-Object -ExpandProperty result"') do set AUTH_TOKEN=%%a

if "%AUTH_TOKEN%"=="" (
    echo Ошибка получения токена!
    pause
    exit /b 1
)

REM --- [Регистрация хоста] ---
echo Регистрация хоста на сервере Zabbix...
set HOST_JSON={"jsonrpc":"2.0","method":"host.create","params":{"host":"%HOSTNAME%","interfaces":[{"type":1,"main":1,"useip":0,"port":"10050"}],"groups":[{"groupid":"%GROUPID%"}],"templates":[{"templateid":"%TEMPLATE_ID%"}]},"auth":"%AUTH_TOKEN%","id":1}

REM Выполняем запрос на регистрацию хоста
for /f "delims=" %%a in ('powershell -Command "$response = Invoke-WebRequest -Uri 'http://%ZABBIX_SERVER%:%ZABBIX_PORT%/api_jsonrpc.php' -Method Post -Body '%HOST_JSON%' -ContentType 'application/json'; $response.Content | ConvertFrom-Json | Select-Object -ExpandProperty result"') do set HOST_RESULT=%%a

if "%HOST_RESULT%"=="" (
    echo Ошибка: Не удалось зарегистрировать хост на сервере Zabbix.
    pause
    exit /b 1
)

echo Хост успешно зарегистрирован на сервере Zabbix!
echo Установка и настройка Zabbix Agent 2 завершена!
echo Hostname: %HOSTNAME%
pause