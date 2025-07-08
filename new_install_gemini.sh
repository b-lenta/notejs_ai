#!/bin/bash

# Останавливаем выполнение скрипта при любой ошибке
set -e

# --- Переменные конфигурации ---
GO_VERSION="1.22.5"
GENSYN_REPO="https://github.com/gensyn-ai/rl-swarm.git"
BINARY_NAME="swarm-gpu"
SERVICE_NAME="gensynd"

# --- Цвета для вывода ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# --- Функции ---

# Функция для установки системных зависимостей
install_dependencies() {
    echo -e "${YELLOW}---> Обновление пакетов и установка зависимостей...${NC}"
    sudo apt-get update
    sudo apt-get install -y git curl build-essential pkg-config libssl-dev
    echo -e "${GREEN}---> Зависимости установлены.${NC}\n"
}

# Функция для установки Go
install_go() {
    echo -e "${YELLOW}---> Установка языка Go...${NC}"
    if command -v go &>/dev/null && [[ "$(go version)" == *"$GO_VERSION"* ]]; then
        echo -e "${GREEN}---> Go версии $GO_VERSION уже установлен.${NC}\n"
        return
    fi
    
    echo "Скачивание Go v$GO_VERSION..."
    curl -L -o go.tar.gz "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz"
    
    echo "Удаление старой версии (если есть) и установка новой..."
    sudo rm -rf /usr/local/go
    sudo tar -C /usr/local -xzf go.tar.gz
    rm go.tar.gz
    
    echo "Настройка системных путей для Go..."
    echo 'export PATH=$PATH:/usr/local/go/bin' | sudo tee /etc/profile.d/go.sh > /dev/null
    source /etc/profile.d/go.sh
    
    echo -e "${GREEN}---> Go установлен. Версия: $(go version)${NC}\n"
}

# Функция для сборки ноды из исходного кода
build_node() {
    echo -e "${YELLOW}---> Сборка ноды Gensyn для GPU...${NC}"
    
    # Клонируем в временную папку для чистоты
    rm -rf /tmp/rl-swarm
    git clone $GENSYN_REPO /tmp/rl-swarm
    cd /tmp/rl-swarm
    
    echo "Запуск компиляции (это может занять несколько минут)..."
    make swarm-gpu
    
    echo "Перемещение скомпилированного файла в системную директорию..."
    sudo mv build/$BINARY_NAME /usr/local/bin/
    
    # Очистка
    cd ~
    rm -rf /tmp/rl-swarm
    
    echo -e "${GREEN}---> Нода успешно скомпилирована и установлена.${NC}\n"
}

# Функция для создания и настройки системной службы
setup_service() {
    echo -e "${YELLOW}---> Настройка системной службы для автозапуска...${NC}"
    
    # Запрос токена у пользователя
    read -p "Пожалуйста, введите ваш токен Hugging Face (HF_TOKEN): " HF_TOKEN
    if [ -z "$HF_TOKEN" ]; then
        echo "Ошибка: токен не может быть пустым."
        exit 1
    fi
    
    echo "Создание файла службы $SERVICE_NAME.service..."
    
    # Создание файла службы с помощью heredoc
    sudo bash -c "cat > /etc/systemd/system/${SERVICE_NAME}.service" << EOF
[Unit]
Description=Gensyn Node
After=network.target

[Service]
User=$(whoami)
ExecStart=/usr/local/bin/$BINARY_NAME start
Environment="HF_TOKEN=${HF_TOKEN}"
Restart=always
RestartSec=10
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

    echo "Перезагрузка демона systemd и запуск службы..."
    sudo systemctl daemon-reload
    sudo systemctl enable $SERVICE_NAME
    sudo systemctl start $SERVICE_NAME
    
    echo -e "${GREEN}---> Служба ${SERVICE_NAME} создана и запущена.${NC}\n"
}


# --- Основной блок выполнения ---
main() {
    install_dependencies
    install_go
    build_node
    setup_service
    
    echo -e "${GREEN}🎉 Установка Gensyn успешно завершена!${NC}"
    echo "Вы можете проверить статус ноды с помощью команды:"
    echo -e "${YELLOW}sudo systemctl status ${SERVICE_NAME}${NC}"
    echo "А посмотреть логи в реальном времени можно так:"
    echo -e "${YELLOW}sudo journalctl -u ${SERVICE_NAME} -f${NC}"
}

# Запуск основной функции
main
