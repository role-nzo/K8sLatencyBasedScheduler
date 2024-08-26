!/bin/bash

# Define the URL you want to query
URL="127.0.0.1:30107"

# Loop indefinitely
while true; do
    curl -w "\
time_total:       %{time_total}s\n" \
-o /dev/null "$URL"

    # Wait for 30 seconds
    sleep 20
done