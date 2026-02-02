#!/bin/bash

BASE_URL=${SPEACHES_BASE_URL:-"http://localhost:8000"}
BASE_URL=${BASE_URL%/}

# Check dependencies
if ! command -v curl &> /dev/null; then
    echo "Error: curl is required but not installed."
    exit 1
fi

# Function to handle direct download
download_direct() {
    local model=$1
    echo "POST request to: ${BASE_URL}/v1/models/${model}"
    curl -X POST "${BASE_URL}/v1/models/${model}"
}

# If argument provided, use direct mode
if [ -n "$1" ]; then
    download_direct "$1"
    exit 0
fi

# Interactive mode
echo "Fetching model registry from ${BASE_URL}/v1/registry..."
RESPONSE=$(curl -s "${BASE_URL}/v1/registry")

if [ -z "$RESPONSE" ]; then
    echo "Error: Failed to fetch registry. Is the server running?"
    exit 1
fi

FILTER="Systran"

if command -v jq &> /dev/null; then
    MODELS_RAW=$(echo "$RESPONSE" | jq -r --arg filter "$FILTER" '.data[] | select(.id | contains($filter)) | "\(.id)|\(.language // .languages // [] | join(","))"')
else
    echo "⚠️  'jq' not found. Using basic text parsing (might be fragile)..."
    MODELS_RAW=$(echo "$RESPONSE" | grep -o '"id":"[^"]*"' | cut -d'"' -f4 | grep "$FILTER")
fi

if [ -z "$MODELS_RAW" ]; then
    echo "No models found."
    exit 0
fi

IFS=$'\n' read -rd '' -a MODEL_LIST <<< "$MODELS_RAW"

IDS=()
LANGS=()

for item in "${MODEL_LIST[@]}"; do
    if [[ "$item" == *"|"* ]]; then
        ID="${item%%|*}"
        LANG="${item#*|}"
        if [ ${#LANG} -gt 30 ]; then
            LANG="${LANG:0:27}..."
        fi
    else
        ID="$item"
        LANG="N/A"
    fi
    IDS+=("$ID")
    LANGS+=("$LANG")
done

SELECTED=0
TOTAL=${#IDS[@]}
VIEW_HEIGHT=10  # Number of items to show at once

tput civis

cleanup() {
    tput cnorm
    exit 0
}
trap cleanup SIGINT SIGTERM

draw_menu() {
    tput clear
    
    echo "Select a model to download (Use Arrow Keys, Enter to select, 'q' to quit):"
    echo "------------------------------------------------------------"
    printf "%-40s | %s\n" "Model ID" "Languages"
    echo "------------------------------------------------------------"

    # Calculate scroll window
    local start_idx=$((SELECTED - VIEW_HEIGHT / 2))
    if [ $start_idx -lt 0 ]; then start_idx=0; fi
    local end_idx=$((start_idx + VIEW_HEIGHT))
    if [ $end_idx -gt $TOTAL ]; then 
        end_idx=$TOTAL
        start_idx=$((TOTAL - VIEW_HEIGHT))
        if [ $start_idx -lt 0 ]; then start_idx=0; fi
    fi

    for ((i=start_idx; i<end_idx; i++)); do
        if [ $i -eq $SELECTED ]; then
            printf "\e[32m > %-38s | %s\e[0m\n" "${IDS[$i]}" "${LANGS[$i]}"
        else
            printf "   %-38s | %s\n" "${IDS[$i]}" "${LANGS[$i]}"
        fi
    done
    
    echo "------------------------------------------------------------"
    echo "Showing $((start_idx+1))-$end_idx of $TOTAL models"
}

while true; do
    draw_menu
    
    read -rsn1 key
    
    if [[ $key == $'\x1b' ]]; then
        read -rsn2 key
        if [[ $key == "[A" ]]; then
            ((SELECTED--))
            if [ $SELECTED -lt 0 ]; then SELECTED=0; fi
        elif [[ $key == "[B" ]]; then
            ((SELECTED++))
            if [ $SELECTED -ge $TOTAL ]; then SELECTED=$((TOTAL-1)); fi
        fi
    elif [[ $key == "" ]]; then
        MODEL_ID="${IDS[$SELECTED]}"
        tput cnorm
        echo ""
        echo "Selected model: $MODEL_ID"
        read -p "Download $MODEL_ID? (y/n): " confirm
        if [[ $confirm == "y" || $confirm == "Y" ]]; then
             download_direct "$MODEL_ID"
        fi
        break
    elif [[ $key == "q" ]]; then
        cleanup
    fi
done

tput cnorm
