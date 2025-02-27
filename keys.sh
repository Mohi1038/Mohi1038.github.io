#!/bin/bash

# Check if at least one key is provided
if [ $# -eq 0 ]; then
    echo "Usage: $0 <public_key1> [<public_key2> ...]"
    exit 1
fi

# Ensure authorized_keys file exists with correct permissions
AUTH_KEYS_PATH=~/.ssh/authorized_keys
touch "$AUTH_KEYS_PATH"
chmod 600 "$AUTH_KEYS_PATH"

# Append each provided key to authorized_keys
for key in "$@"; do
    # Check if the key file exists
    if [ ! -f "$key" ]; then
        echo "Error: Key file $key not found"
        continue
    fi

    # Append the key, ensuring a newline between keys
    cat "$key" >> "$AUTH_KEYS_PATH"
    echo "" >> "$AUTH_KEYS_PATH"
done

echo "Public keys appended successfully to $AUTH_KEYS_PATH"