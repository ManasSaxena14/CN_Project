#!/bin/bash

set -e

source ./config.env

DOMAIN="app.$PROJECT_DOMAIN"

echo ""
echo "=========================================="
echo " PHASE 1 NETWORK TEST"
echo "=========================================="

echo ""
echo "1. Testing DNS..."
echo "------------------------------------------"

dig +short "$DOMAIN"

DNS_RESULT=$(dig +short "$DOMAIN")

if [ "$DNS_RESULT" = "$MAC2_IP" ]; then
    echo "✓ DNS PASS"
else
    echo "✗ DNS FAIL"
    echo "Expected: $MAC2_IP"
    echo "Got: $DNS_RESULT"
fi


echo ""
echo "2. Testing Backend A..."
echo "------------------------------------------"

curl -s \
    "http://$MAC3_IP:$BACKEND_A_PORT/api/status"

echo ""


echo ""
echo "3. Testing Backend B..."
echo "------------------------------------------"

curl -s \
    "http://$MAC4_IP:$BACKEND_B_PORT/api/status"

echo ""


echo ""
echo "4. Testing HTTPS..."
echo "------------------------------------------"

curl -I \
    "https://$DOMAIN/api/status"

echo ""


echo ""
echo "5. Testing load balancing..."
echo "------------------------------------------"

for i in {1..10}
do

    echo -n "Request $i: "

    curl -s \
        -D - \
        -o /dev/null \
        "https://$DOMAIN/api/status" |
        grep -i "^X-Backend:" |
        tr -d '\r'

done


echo ""
echo "6. Testing /api/cache caching (Task F)..."
echo "------------------------------------------"

echo ""
echo "6a. Verify no-store on /api/status (must NOT be cached):"
curl -sI "https://$DOMAIN/api/status" | grep -Ei "cache-control|etag"

echo ""
echo "6b. First request to /api/cache - expect 200 + ETag + Cache-Control: max-age=60:"
CACHE_RESP=$(curl -sI "https://$DOMAIN/api/cache")
echo "$CACHE_RESP" | grep -Ei "HTTP/|cache-control|etag|x-backend"

ETAG=$(echo "$CACHE_RESP" | grep -i "^etag:" | tr -d '\r' | awk '{print $2}')
echo ""
echo "  Captured ETag: $ETAG"

echo ""
echo "6c. Conditional request with If-None-Match (expect 304 every time):"
for i in {1..6}; do
    STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
        -H "If-None-Match: $ETAG" \
        "https://$DOMAIN/api/cache")
    echo "  Request $i: HTTP $STATUS  (want 304)"
done

echo ""
echo "6d. Confirm ETag is IDENTICAL on both backends directly:"
ETAG_A=$(curl -sI "http://$MAC3_IP:$BACKEND_A_PORT/api/cache" | grep -i "^etag:" | tr -d '\r' | awk '{print $2}')
ETAG_B=$(curl -sI "http://$MAC4_IP:$BACKEND_B_PORT/api/cache" | grep -i "^etag:" | tr -d '\r' | awk '{print $2}')
echo "  Backend A ETag: $ETAG_A"
echo "  Backend B ETag: $ETAG_B"
if [ "$ETAG_A" = "$ETAG_B" ]; then
    echo "  \u2713 CACHING PASS - ETags match across backends"
else
    echo "  \u2717 CACHING FAIL - ETags differ (body is not identical)"
fi

echo ""
echo "=========================================="
echo " TEST COMPLETE"
echo "=========================================="