#!/bin/bash

set -euo pipefail

base64var() {
    printf "$1" | base64stream
}

base64stream() {
    base64 | tr '/+' '_-' | tr -d '=\n'
}

scope="$1"
sa_email="$2"
private_key=$(echo "\"$3\"" | jq -r .)
if [ -z $private_key ]
then
  exit 1
fi
valid_for_sec=${4:-3600}

header='{"alg":"RS256","typ":"JWT"}'
claim=$(cat <<EOF | jq -c
  {
    "iss": "$sa_email",
    "scope": "$scope",
    "aud": "https://www.googleapis.com/oauth2/v4/token",
    "exp": $(($(date +%s) + $valid_for_sec)),
    "iat": $(date +%s)
  }
EOF
)

request_body="$(base64var "$header").$(base64var "$claim")"
signature=$(openssl dgst -sha256 -sign <(echo "$private_key") <(printf "$request_body") | base64stream)
jwt_token="$request_body.$signature"

token="$(curl -s -X POST https://www.googleapis.com/oauth2/v4/token --data-urlencode 'grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer' --data-urlencode "assertion=$jwt_token" | jq -r .access_token)"
printf $token