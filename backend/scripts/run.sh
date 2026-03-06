#!/bin/bash
# Run FastAPI with environment variables from .env file

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$PROJECT_DIR/.env"

if [ ! -f "$ENV_FILE" ]; then
    echo "Error: .env file not found at $ENV_FILE"
    exit 1
fi

# Export environment variables from .env file
while IFS='=' read -r key value || [ -n "$key" ]; do
    # Skip empty lines and comments
    [[ -z "$key" || "$key" =~ ^# ]] && continue
    # Remove any carriage returns and trim whitespace
    key=$(echo "$key" | tr -d '\r' | xargs)
    value=$(echo "$value" | tr -d '\r')
    if [ -n "$key" ] && [ -n "$value" ]; then
        export "$key=$value"
    fi
done < "$ENV_FILE"

cd "$PROJECT_DIR"

# Pass any additional arguments to uvicorn
# Can we also run mlflow server here?

echo "Running: uvicorn app.main:app $@"
uvicorn app.main:app "$@"  
#mlflow server --host 0.0.0.0 --port 5000
