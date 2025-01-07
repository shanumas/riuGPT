#!/bin/bash

#####################################
#        UTILITY FUNCTIONS          #
#####################################

# Check if Docker is installed; if not, install it.
install_docker() {
    echo "Docker is not installed. Installing Docker..."
    # Install dependencies
    sudo apt update
    sudo apt install -y apt-transport-https ca-certificates curl software-properties-common
    # Add Docker GPG key
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    # Add Docker repository
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] \
    https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
    | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    # Install Docker
    sudo apt update
    sudo apt install -y docker-ce docker-ce-cli containerd.io
    echo "Docker installed successfully."
}

# Check if Docker is already installed; install if not.
check_docker_installed() {
    if ! command -v docker &> /dev/null; then
        install_docker
    else
        echo "Docker is already installed."
    fi
}

# Ensure Docker is installed; then verify it’s running. 
# If not running, warn the user to start it manually.
check_and_start_docker() {
    check_docker_installed

    # Check if Docker is running (i.e., `docker info` works).
    if ! docker info > /dev/null 2>&1; then
        echo "Docker is not running. Please start Docker manually, then rerun this script if needed."
        exit 1
    fi

    echo "Docker is running."
}

#####################################
#           MAIN CHOICES            #
#####################################

# Prompt user for a choice (currently unused in this snippet, but shown for completeness).
prompt_user() {
    echo "Do you want to:"
    echo "1. Use DocsGPT public API (simple and free)"
    echo "2. Download the language model locally (12GB)"
    echo "3. Use the OpenAI API (requires an API key)"
    read -p "Enter your choice (1, 2 or 3): " choice
}

# Download the language model locally and build the local Docker environment.
download_locally() {
    echo "LLM_NAME=llama.cpp" > .env
    echo "VITE_API_STREAMING=true" >> .env
    echo "EMBEDDINGS_NAME=huggingface_sentence-transformers/all-mpnet-base-v2" >> .env
    echo "The .env file has been created with LLM_NAME set to llama.cpp."

    # Create models directory if needed
    mkdir -p models

    # Download the model only if it doesn't exist
    echo "Downloading the model..."
    if [ ! -f models/docsgpt-7b-f16.gguf ]; then
        wget -P models https://d3dg1063dc54p9.cloudfront.net/models/docsgpt-7b-f16.gguf
        echo "Model downloaded to models directory."
    else
        echo "Model already exists."
    fi

    # Ensure Docker is installed and running
    check_and_start_docker

    # Build and run Docker containers
    docker-compose -f docker-compose-local.yaml build && docker-compose -f docker-compose-local.yaml up -d

    # Install Python dependencies
    pip install -r application/requirements.txt llama-cpp-python sentence-transformers

    # Export environment variables for Flask/Celery
    export LLM_NAME=llama.cpp
    export EMBEDDINGS_NAME=huggingface_sentence-transformers/all-mpnet-base-v2
    export FLASK_APP=application/app.py
    export FLASK_DEBUG=true
    export CELERY_BROKER_URL=redis://localhost:6379/0
    export CELERY_RESULT_BACKEND=redis://localhost:6379/1

    echo "The application is now running on http://localhost:5173"
    echo "You can stop the application by pressing Ctrl + C and then running:"
    echo "  pkill -f 'flask run' && docker-compose down"

    # Start Flask + Celery in background
    flask run --host=0.0.0.0 --port=7091 &
    celery -A application.app.celery worker -l INFO
}

# Use OpenAI API (requires user to enter an API key)
use_openai() {
    read -p "Please enter your OpenAI API key: " api_key
    echo "API_KEY=$api_key" > .env
    echo "LLM_NAME=openai" >> .env
    echo "VITE_API_STREAMING=true" >> .env
    echo "The .env file has been created with API_KEY set to your provided key."

    check_and_start_docker
    docker-compose build && docker-compose up -d

    echo "The application will run on http://localhost:5173"
    echo "You can stop the application by running: docker-compose down"
}

# Use DocsGPT (public API)
use_docsgpt() {
    echo "LLM_NAME=docsgpt" > .env
    echo "VITE_API_STREAMING=true" >> .env
    echo "The .env file has been created with docsgpt as your LLM."

    check_and_start_docker
    docker-compose build && docker-compose up -d

    echo "The application will run on http://localhost:5173"
    echo "You can stop the application by running: docker-compose down"
}

#####################################
#            SCRIPT START           #
#####################################

# If you want to actually use the prompt, uncomment and handle the user’s choice:
# prompt_user
# case "$choice" in
#     1) use_docsgpt ;;
#     2) download_locally ;;
#     3) use_openai ;;
#     *) echo "Invalid choice. Exiting." ;;
# esac

# For now, you hard-coded `use_docsgpt`:
use_docsgpt
