#!/bin/bash

# Function to prompt the user for their choice
prompt_user() {
    echo "Do you want to:"
    echo "1. Use DocsGPT public API (simple and free)"
    echo "2. Download the language model locally (12GB)"
    echo "3. Use the OpenAI API (requires an API key)"
    read -p "Enter your choice (1, 2 or 3): " choice
}

# Function to install Docker if not installed
install_docker() {
    echo "Docker is not installed. Installing Docker..."
    # Install dependencies
    sudo apt update
    sudo apt install -y apt-transport-https ca-certificates curl software-properties-common
    # Add Docker GPG key
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    # Add Docker repository
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    # Install Docker
    sudo apt update
    sudo apt install -y docker-ce docker-ce-cli containerd.io
    echo "Docker installed successfully."
}

# Function to check if Docker is installed
check_docker_installed() {
    if ! command -v docker &> /dev/null; then
        install_docker
    else
        echo "Docker is already installed."
    fi
}

check_and_start_docker() {
    check_docker_installed

    # Check if Docker is running
    if ! docker info > /dev/null 2>&1; then
        echo "Docker is not running. Starting Docker..."
        if ! pgrep -x "dockerd" > /dev/null; then
            echo "Starting Docker daemon..."
            sudo dockerd > /dev/null 2>&1 &
            sleep 5
        fi

        # Verify Docker is running
        if ! docker info > /dev/null 2>&1; then
            echo "Failed to start Docker. Please start it manually."
            exit 1
        fi
    fi
    echo "Docker is running."
}

# Function to handle the choice to download the model locally
download_locally() {
    echo "LLM_NAME=llama.cpp" > .env
    echo "VITE_API_STREAMING=true" >> .env
    echo "EMBEDDINGS_NAME=huggingface_sentence-transformers/all-mpnet-base-v2" >> .env
    echo "The .env file has been created with LLM_NAME set to llama.cpp."

    # Creating the directory if it does not exist
    mkdir -p models
    
    # Downloading the model to the specific directory
    echo "Downloading the model..."
    if [ ! -f models/docsgpt-7b-f16.gguf ]; then
        wget -P models https://d3dg1063dc54p9.cloudfront.net/models/docsgpt-7b-f16.gguf
        echo "Model downloaded to models directory."
    else
        echo "Model already exists."
    fi

    # Call the function to check and start Docker if needed
    check_and_start_docker

    docker-compose -f docker-compose-local.yaml build && docker-compose -f docker-compose-local.yaml up -d
    pip install -r application/requirements.txt llama-cpp-python sentence-transformers
    export LLM_NAME=llama.cpp
    export EMBEDDINGS_NAME=huggingface_sentence-transformers/all-mpnet-base-v2
    export FLASK_APP=application/app.py
    export FLASK_DEBUG=true
    export CELERY_BROKER_URL=redis://localhost:6379/0
    export CELERY_RESULT_BACKEND=redis://localhost:6379/1
    echo "The application is now running on http://localhost:5173"
    echo "You can stop the application by running the following command:"
    echo "Ctrl + C and then"
    echo "pkill -f 'flask run' && docker-compose down"
    flask run --host=0.0.0.0 --port=7091 &
    celery -A application.app.celery worker -l INFO
}

# Function to handle the choice to use the OpenAI API
use_openai() {
    read -p "Please enter your OpenAI API key: " api_key
    echo "API_KEY=$api_key" > .env
    echo "LLM_NAME=openai" >> .env
    echo "VITE_API_STREAMING=true" >> .env
    echo "The .env file has been created with API_KEY set to your provided key."

    # Call the function to check and start Docker if needed
    check_and_start_docker
    
    docker-compose build && docker-compose up -d

    echo "The application will run on http://localhost:5173"
    echo "You can stop the application by running the following command:"
    echo "docker-compose down"
}

use_docsgpt() {
    echo "LLM_NAME=docsgpt" > .env
    echo "VITE_API_STREAMING=true" >> .env
    echo "The .env file has been created with API_KEY set to your provided key."

    # Call the function to check and start Docker if needed
    check_and_start_docker

    docker-compose build && docker-compose up -d

    echo "The application will run on http://localhost:5173"
    echo "You can stop the application by running the following command:"
    echo "docker-compose down"
}

# Prompt the user for their choice
use_docsgpt
