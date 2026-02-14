#!/bin/bash

# CPU Info Debug Script
echo "=== CPU Info Debug ==="
echo ""

# Check available commands
echo "1. Available commands:"
command -v bc >/dev/null 2>&1 && echo "   ✓ bc available" || echo "   ✗ bc NOT available"
command -v lscpu >/dev/null 2>&1 && echo "   ✓ lscpu available" || echo "   ✗ lscpu NOT available"
[ -f /proc/cpuinfo ] && echo "   ✓ /proc/cpuinfo exists" || echo "   ✗ /proc/cpuinfo NOT found"
[ -f /proc/loadavg ] && echo "   ✓ /proc/loadavg exists" || echo "   ✗ /proc/loadavg NOT found"

echo ""
echo "2. Testing /proc/loadavg:"
if [ -f /proc/loadavg ]; then
    echo "   Raw content:"
    cat /proc/loadavg | cat -A | sed 's/^/     /'
    echo "   First field:"
    LOAD=$(cat /proc/loadavg | awk '{print $1}')
    echo "   [$LOAD]"
else
    echo "   ERROR: /proc/loadavg not found"
fi

echo ""
echo "3. Testing CPU cores:"
CORES=$(nproc 2>/dev/null || echo "ERROR")
echo "   Cores: [$CORES]"

echo ""
echo "4. Testing CPU calculation:"
if [ -n "$LOAD" ] && [ "$LOAD" != "ERROR" ] && [ -n "$CORES" ] && [ "$CORES" != "ERROR" ]; then
    if command -v bc >/dev/null 2>&1; then
        USAGE=$(echo "scale=1; $LOAD * 100 / $CORES" | bc -l)
        echo "   BC result: [$USAGE]"
    fi
    USAGE2=$(awk "BEGIN {printf \"%.1f\", $LOAD * 100 / $CORES}")
    echo "   AWK result: [$USAGE2]"
else
    echo "   ERROR: Cannot calculate (LOAD=[$LOAD], CORES=[$CORES])"
fi

echo ""
echo "5. Testing /proc/cpuinfo:"
if [ -f /proc/cpuinfo ]; then
    echo "   Model name lines:"
    grep 'model name' /proc/cpuinfo | cat -A | sed 's/^/     /' | head -n 3
    echo ""
    echo "   First model name:"
    MODEL=$(grep -m 1 'model name' /proc/cpuinfo | awk -F: '{for(i=2;i<=NF;i++) printf "%s ", $i}' | xargs)
    echo "   [$MODEL]"
else
    echo "   ERROR: /proc/cpuinfo not found"
fi

echo ""
echo "6. Testing lscpu:"
if command -v lscpu >/dev/null 2>&1; then
    echo "   Model name line:"
    timeout 1 lscpu | grep "Model name" | cat -A | sed 's/^/     /'
    echo ""
    echo "   Extracted model:"
    MODEL2=$(timeout 1 lscpu 2>/dev/null | grep "Model name" | sed 's/Model name: *//' | sed 's/BIOS.*//' | xargs)
    echo "   [$MODEL2]"
else
    echo "   ERROR: lscpu not available"
fi

echo ""
echo "=== Debug Complete ==="
