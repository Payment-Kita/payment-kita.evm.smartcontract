#!/bin/bash
# TokenSwapper Verification Status Checker with Auto-Refresh

CONTRACT="0x0b482cc728a9aaf9bfbfdd24247b181af0238295"
CHAIN_ID="42161"
API_KEY="$ARBISCAN_API_KEY"
AUTO_REFRESH=${1:-false}

check_status() {
    # Get raw response
    RAW_RESPONSE=$(curl -s "https://api.etherscan.io/v2/api?chainid=$CHAIN_ID&module=contract&action=getsourcecode&address=$CONTRACT&apikey=$API_KEY")
    
    if [ -z "$RAW_RESPONSE" ]; then
        echo "❌ Empty API response"
        return 1
    fi
    
    # Parse response
    STATUS=$(echo "$RAW_RESPONSE" | jq -r '.result[0].VerificationStatus' 2>/dev/null)
    COMPILER=$(echo "$RAW_RESPONSE" | jq -r '.result[0].CompilerVersion' 2>/dev/null)
    OPTIMIZATION=$(echo "$RAW_RESPONSE" | jq -r '.result[0].OptimizationUsed' 2>/dev/null)
    SOURCE_CODE=$(echo "$RAW_RESPONSE" | jq -r '.result[0].SourceCode' 2>/dev/null)
    
    # Calculate source code length
    if [ -n "$SOURCE_CODE" ] && [ "$SOURCE_CODE" != "" ] && [ "$SOURCE_CODE" != "null" ]; then
        SOURCE_LENGTH=${#SOURCE_CODE}
    else
        SOURCE_LENGTH=0
    fi
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📊 TokenSwapper Verification Status"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Contract: $CONTRACT"
    echo "Chain: Arbitrum (42161)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Verification Status: ${STATUS:-⏳ Pending}"
    echo "Compiler Version: ${COMPILER:-<not set>}"
    echo "Optimization Used: ${OPTIMIZATION:-<not set>}"
    echo "Source Code Length: $SOURCE_LENGTH bytes"
    echo ""
    
    if [ "$STATUS" = "Pass - Verified" ]; then
        echo "✅ VERIFICATION SUCCESSFUL!"
        echo ""
        echo "Compiler: $COMPILER"
        echo "Optimization: $OPTIMIZATION"
        echo ""
        echo "🔗 View on Arbiscan: https://arbiscan.io/address/$CONTRACT#code"
        return 0
    elif [ "$STATUS" = "Fail - Verification failed" ]; then
        echo "❌ VERIFICATION FAILED!"
        echo ""
        echo "Please check the error on Arbiscan and resubmit."
        return 1
    else
        echo "⏳ VERIFICATION PENDING..."
        echo ""
        echo "This is normal - verification typically takes 10-30 minutes."
        echo ""
        echo "🔗 Check manually: https://arbiscan.io/address/$CONTRACT#code"
        return 2
    fi
}

# Run check
check_status
RESULT=$?

# Auto-refresh if requested
if [ "$AUTO_REFRESH" = "--watch" ] || [ "$AUTO_REFRESH" = "-w" ]; then
    echo ""
    echo "🔄 Auto-refresh enabled (Ctrl+C to stop)..."
    echo ""
    while [ $RESULT -ne 0 ] && [ $RESULT -ne 1 ]; do
        sleep 30
        clear
        check_status
        RESULT=$?
    done
fi

exit $RESULT
