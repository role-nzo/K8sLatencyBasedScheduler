#!/bin/bash

# Define the URL you want to query
URL="127.0.0.1:30107"

# Loop indefinitely
for i in {0..4}; do
    curl -w "\
time_total:       %{time_total}s\n" \
-o /dev/null "$URL"

    # Wait for 30 seconds
    sleep 1
done