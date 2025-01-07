#!/bin/bash

#####################################
#        UTILITY FUNCTIONS          #
#####################################

# Prompt the user for a choice (optional if you want an interactive menu)
prompt_user() {
    echo "Do you want to:"
    echo "1. Use DocsGPT public API (simple and free)"
    echo "2. Download the language model locally (12GB)"
    echo "3. Use the OpenAI API (requires an API key)"
    read -p "Enter your choice (1, 2, or 3): " choice
}

# Install Docker if not already installed
install_docker() {
    echo "Docker is not installed. Installing Docker..."
    # Install dependencies
    sudo apt update
    sudo apt install -y apt-transport-https ca-certificates curl software-properties-common
    # Add Docker GPG key
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
        | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    # Add Docker repository
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] \
https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
    | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    # Install Docker
    sudo apt update
    sudo apt install -y docker-ce docker-ce-cli containerd.io
    echo "Docker installed successfully."
}

# Check if Docker is installed; install if not
check_docker_installed() {
    if ! command -v docker &> /dev/null; then
        install_docker
    else
        echo "Docker is already installed."
    fi
}

# Check if Docker is running; if not, try to start via systemctl
check_and_start_docker() {
    check_docker_installed

    # Check if Docker is running
    if ! docker info > /dev/null 2>&1; then
        echo "Docker is not running. Attempting to start via systemctl..."
        sudo service docker start
        sleep 5  # Give Docker some time to start

        if ! docker info > /dev/null 2>&1; then
            echo "Failed to start Docker via systemctl. Please start it manually."
            exit 1
        fi
    fi
    echo "Docker is running."
}

#####################################
#           MAIN CHOICES            #
#####################################

# 1) Download the language model locally (12GB)
download_locally() {
    echo "LLM_NAME=llama.cpp" > .env
    echo "VITE_API_STREAMING=true" >> .env
    echo "EMBEDDINGS_NAME=huggingface_sentence-transformers/all-mpnet-base-v2" >> .env
    echo "The .env file has been created with LLM_NAME set to llama.cpp."

    # Create the models directory if it does not exist
    mkdir -p models
    
    # Download the model if not present
    echo "Downloading the model..."
    if [ ! -f models/docsgpt-7b-f16.gguf ]; then
        wget -P models https://d3dg1063dc54p9.cloudfront.net/models/docsgpt-7b-f16.gguf
        echo "Model downloaded to models/ directory."
    else
        echo "Model already exists."
    fi

    # Ensure Docker is running
    check_and_start_docker

    # Build & run Docker Compose in local mode
    docker-compose -f docker-compose-local.yaml build && docker-compose -f docker-compose-local.yaml up -d

    # Install Python dependencies for your application
    pip install -r application/requirements.txt llama-cpp-python sentence-transformers

    # Export environment variables for Flask + Celery
    export LLM_NAME=llama.cpp
    export EMBEDDINGS_NAME=huggingface_sentence-transformers/all-mpnet-base-v2
    export FLASK_APP=application/app.py
    export FLASK_DEBUG=true
    export CELERY_BROKER_URL=redis://localhost:6379/0
    export CELERY_RESULT_BACKEND=redis://localhost:6379/1

    # Announce success
    echo "The application is now running on http://localhost:5173"
    echo "You can stop the application by pressing Ctrl + C and then running:"
    echo "  pkill -f 'flask run' && docker-compose down"

    # Start Flask & Celery in the background
    flask run --host=0.0.0.0 --port=7091 &
    celery -A application.app.celery worker -l INFO
}

# 2) Use OpenAI API (requires user to enter an API key)
use_openai() {
    read -p "Please enter your OpenAI API key: " api_key
    echo "API_KEY=$api_key" > .env
    echo "LLM_NAME=openai" >> .env
    echo "VITE_API_STREAMING=true" >> .env
    echo "The .env file has been created with your OpenAI API key."

    # Ensure Docker is running
    check_and_start_docker

    # Build & run the default Docker Compose
    docker-compose build && docker-compose up -d

    # Announce success
    echo "The application will run on http://localhost:5173"
    echo "You can stop it by running:  docker-compose down"
}

# 3) Use DocsGPT public API
use_docsgpt() {
    echo "LLM_NAME=docsgpt" > .env
    echo "VITE_API_STREAMING=true" >> .env
    echo "The .env file has been created with docsgpt as your LLM."

    # Ensure Docker is running
    check_and_start_docker

    # Build & run the default Docker Compose
    docker-compose build && docker-compose up -d

    # Announce success
    echo "The application will run on http://localhost:5173"
    echo "You can stop it by running:  docker-compose down"
}

#####################################
#            SCRIPT START           #
#####################################

# If you want an interactive prompt:
# prompt_user
# case "$choice" in
#     1) use_docsgpt ;;
#     2) download_locally ;;
#     3) use_openai ;;
#     *) echo "Invalid choice. Exiting." ;;
# esac

# For now, you can hard-code whichever function you want to call, e.g.:
use_docsgpt
