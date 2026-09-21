export PATH=/usr/local/go/bin:$PATH
set -u
cd "$HOME"
mkdir -p fd2build && cd fd2build
go mod init fd2probe >/dev/null 2>&1 || true
echo "=== go version / get rclone v1.75.1 ==="
go version
go get github.com/rclone/rclone@v1.75.1 2>&1 | tail -3
echo "=== building librclone.so ==="
CGO_ENABLED=1 GOOS=linux GOARCH=amd64 go build -tags noselfupdate -trimpath \
  -ldflags "-s -w -X github.com/rclone/rclone/fs.Version=v1.75.1" \
  --buildmode=c-shared -o /tmp/librclone.so github.com/rclone/rclone/librclone || { echo "BUILD FAILED"; exit 9; }
ls -lh /tmp/librclone.so
echo "=== compiling harness ==="
gcc -O0 -g /tmp/harness.c -o /tmp/harness -ldl -lpthread || { echo "GCC FAILED"; exit 9; }
echo
echo "############ RUN 1: dup2 BEFORE dlopen ############"
/tmp/harness /tmp/librclone.so before; echo "run1 exit=$?"
echo
echo "############ RUN 2: dup2 AFTER RcloneInitialize ############"
/tmp/harness /tmp/librclone.so after; echo "run2 exit=$?"
echo
echo "############ config left behind ############"
cat "$HOME/.config/rclone/rclone.conf" 2>/dev/null || echo "(none)"
