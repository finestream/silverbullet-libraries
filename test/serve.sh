#!/bin/sh
# Starts SilverBullet (2.12 or newer) in Docker with a space folder as its space "test":
#
#   test/serve.sh <image> <container> <port> <space folder>
#
# SilverBullet 3 has no single-space mode, so the instance is set up as any other: an administrator
# (admin / admin-test-password), the Runtime API on, the space at /test, and an API token of the
# administrator, printed at the end. Its data live in the volume <container>-data, which is made anew.
set -eu
image=$1 container=$2 port=$3 space=$4
url="http://localhost:$port"
password=admin-test-password
volume="$container-data"
cookies=$(mktemp)
trap 'rm -f "$cookies"' EXIT

docker rm -f "$container" >/dev/null 2>&1 || true
docker volume rm "$volume" >/dev/null 2>&1 || true
docker run --rm --entrypoint /silverbullet -v "$volume:/data" "$image" setup /data --admin "admin:$password" >/dev/null
docker run --rm -d --name "$container" -e PUID=0 -p "$port:3000" -v "$volume:/data" -v "$space:/data/spaces/test" "$image" >/dev/null

# api <method> <path> <JSON>: the admin API, with the session of the login; fails on an HTTP error.
api() { curl -fsS -b "$cookies" -c "$cookies" -X "$1" -H 'Content-Type: application/json' -d "$3" "$url/.dashboard/api$2"; }

i=0
until curl -s -o /dev/null -w '%{http_code}' "$url/.dashboard/api/admin/spaces" | grep -q 401; do
	i=$((i + 1))
	[ "$i" -lt 60 ] || { echo "SilverBullet did not start at $url" >&2; exit 1; }
	sleep 1
done
api POST /login "{\"username\":\"admin\",\"password\":\"$password\"}" >/dev/null
api PUT /admin/server-config '{"runtimeApi":true}' >/dev/null
api POST /admin/spaces '{"name":"test","folder":"spaces/test","binding":{"prefix":"/test"},"members":{}}' >/dev/null
token=$(api POST /admin/users/admin/tokens '{"name":"test"}' | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')
echo "SilverBullet at $url/test/ (admin / $password)"
echo "API token: $token"
