/*
 * fd-2 capture harness for librclone (POSIX).
 *
 * Proves (or disproves) the mechanism Phase B of the guided-remote-setup plan
 * depends on for iOS / MAS: redirect fd 2 into a pipe, load librclone, drive an
 * OAuth config/create, and read rclone's auth-URL NOTICE line out of the pipe.
 *
 * argv[1] = path to librclone.so
 * argv[2] = "before" (dup2 before dlopen) or "after" (dup2 after RcloneInitialize)
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <dlfcn.h>
#include <pthread.h>
#include <errno.h>

typedef struct { char *Output; int Status; } RcloneRPCResult;
typedef void (*fn_void)(void);
typedef RcloneRPCResult (*fn_rpc)(char *, char *);

static int   pipe_r = -1;
static char  captured[1 << 20];
static size_t captured_len = 0;
static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;

static void *drain(void *unused) {
  char buf[4096];
  (void)unused;
  for (;;) {
    ssize_t n = read(pipe_r, buf, sizeof(buf) - 1);
    if (n < 0) { if (errno == EINTR) continue; break; }
    if (n == 0) break;
    buf[n] = 0;
    pthread_mutex_lock(&lock);
    if (captured_len + (size_t)n < sizeof(captured)) {
      memcpy(captured + captured_len, buf, (size_t)n);
      captured_len += (size_t)n;
      captured[captured_len] = 0;
    }
    pthread_mutex_unlock(&lock);
    printf("[fd2] %s", buf);
    fflush(stdout);
  }
  return NULL;
}

static int seen(const char *needle) {
  int hit;
  pthread_mutex_lock(&lock);
  hit = (captured_len > 0) && (strstr(captured, needle) != NULL);
  pthread_mutex_unlock(&lock);
  return hit;
}

static void redirect_fd2(void) {
  int fds[2];
  if (pipe(fds) != 0) { perror("pipe"); exit(2); }
  pipe_r = fds[0];
  fflush(stderr);
  if (dup2(fds[1], 2) < 0) { perror("dup2"); exit(2); }
  close(fds[1]);
  printf("[harness] fd 2 redirected; pipe capacity = %d bytes\n",
         fcntl(pipe_r, F_GETPIPE_SZ));
  fflush(stdout);
  pthread_t t;
  pthread_create(&t, NULL, drain, NULL);
  pthread_detach(t);
}

int main(int argc, char **argv) {
  const char *lib   = (argc > 1) ? argv[1] : "./librclone.so";
  const char *order = (argc > 2) ? argv[2] : "before";
  int before = (strcmp(order, "before") == 0);

  printf("[harness] librclone=%s  dup2-order=%s\n", lib, order);
  fflush(stdout);

  if (before) redirect_fd2();

  void *h = dlopen(lib, RTLD_NOW);
  if (!h) { printf("[harness] dlopen FAILED: %s\n", dlerror()); return 2; }

  fn_void init = (fn_void)dlsym(h, "RcloneInitialize");
  fn_rpc  rpc  = (fn_rpc)dlsym(h, "RcloneRPC");
  if (!init || !rpc) { printf("[harness] dlsym FAILED\n"); return 2; }

  init();
  printf("[harness] RcloneInitialize done\n");
  fflush(stdout);

  if (!before) redirect_fd2();

  char m1[] = "core/version";
  char b1[] = "{}";
  RcloneRPCResult v = rpc(m1, b1);
  printf("[harness] core/version status=%d out=%.160s\n", v.Status, v.Output ? v.Output : "(null)");
  fflush(stdout);

  /* Pre-answer the shared-client_id warning and the locality questions so the
     machine walks straight into the blocking OAuth wait, which logs the link. */
  char m2[] = "config/create";
  char b2[] = "{\"name\":\"fd2probe\",\"type\":\"drive\","
              "\"parameters\":{\"config_shared_client_id\":\"true\","
              "\"config_is_local\":\"true\",\"config_auth_no_browser\":\"true\"},"
              "\"opt\":{\"nonInteractive\":true,\"obscure\":true},\"_async\":true}";
  RcloneRPCResult c = rpc(m2, b2);
  printf("[harness] config/create status=%d out=%.400s\n", c.Status, c.Output ? c.Output : "(null)");
  fflush(stdout);

  const char *needle = "127.0.0.1:53682/auth?state=";
  for (int i = 0; i < 150; i++) {
    if (seen(needle)) {
      printf("\n[harness] RESULT: PASS - auth URL captured from fd 2 after %d ms\n", i * 100);
      return 0;
    }
    usleep(100 * 1000);
  }
  printf("\n[harness] RESULT: FAIL - no auth URL on fd 2 within 15s (captured %zu bytes)\n",
         captured_len);
  return 1;
}
