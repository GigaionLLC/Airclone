/// The sign-in page, rendered by the server rather than by Flutter.
///
/// Why server-rendered, when the whole point of this feature is that the UI is
/// the Flutter app: because the app is ~5 MB of JavaScript plus ~40 MB of
/// CanvasKit, and none of it should be handed to someone who has not signed in
/// yet. Gating the bundle behind the session cookie means an unauthenticated
/// visitor — or a scanner that found the port — gets this one small page and
/// nothing else. It also keeps the login flow entirely on the server, so there
/// is no second implementation of "am I signed in" living in the client.
///
/// Self-contained on purpose: no external CSS, no fonts, no images, no
/// analytics. Everything it needs is in the one response, so it works on an
/// air-gapped host and adds no origins to the Content-Security-Policy.
///
/// The inline script carries a per-response [nonce], because the server's CSP
/// is `script-src 'self'` and `'self'` does NOT cover inline script. Without
/// the nonce the browser silently drops the script, the form falls back to a
/// native POST, and the request arrives with no CSRF header and is refused —
/// which is precisely what happened the first time this page met a real
/// browser. A nonce keeps the strict policy AND the single response.
library;

import 'dart:convert';

/// Renders the sign-in page.
///
/// [error] is shown above the form when a previous attempt failed. It is
/// deliberately vague about *why*: "wrong password" and "no such user" must
/// look identical, or the page becomes a username oracle.
String renderLoginPage({required String nonce, String? error, String? notice}) {
  final errorBlock = error == null
      ? ''
      : '<p class="msg error" role="alert">${_escape(error)}</p>';
  final noticeBlock = notice == null
      ? ''
      : '<p class="msg notice">${_escape(notice)}</p>';
  return '''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex, nofollow">
<title>Sign in &middot; Airclone</title>
<style>
  :root {
    color-scheme: dark;
    --bg: #14161a;
    --panel: #1c1f25;
    --line: #2c313a;
    --text: #e6e8ec;
    --muted: #9aa1ad;
    --accent: #4c8dff;
    --error: #ff6b6b;
  }
  * { box-sizing: border-box; }
  body {
    margin: 0; min-height: 100vh; display: grid; place-items: center;
    background: var(--bg); color: var(--text);
    font: 15px/1.5 system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
    padding: 24px;
  }
  main { width: 100%; max-width: 360px; }
  h1 { font-size: 20px; margin: 0 0 4px; font-weight: 600; }
  .sub { color: var(--muted); margin: 0 0 20px; font-size: 13px; }
  form {
    background: var(--panel); border: 1px solid var(--line);
    border-radius: 10px; padding: 20px;
  }
  label { display: block; font-size: 13px; color: var(--muted); margin-bottom: 6px; }
  input {
    width: 100%; padding: 10px 12px; margin-bottom: 14px;
    background: #12141a; color: var(--text);
    border: 1px solid var(--line); border-radius: 6px; font-size: 15px;
  }
  input:focus { outline: 2px solid var(--accent); outline-offset: 1px; border-color: var(--accent); }
  button {
    width: 100%; padding: 10px 12px; border: 0; border-radius: 6px;
    background: var(--accent); color: #fff; font-size: 15px; font-weight: 600;
    cursor: pointer;
  }
  button:disabled { opacity: .6; cursor: default; }
  .msg { font-size: 13px; margin: 0 0 14px; padding: 10px 12px; border-radius: 6px; }
  .error { background: rgba(255,107,107,.12); color: var(--error); border: 1px solid rgba(255,107,107,.3); }
  .notice { background: rgba(76,141,255,.1); color: var(--muted); border: 1px solid rgba(76,141,255,.25); }
  footer { color: var(--muted); font-size: 12px; margin-top: 16px; text-align: center; }
</style>
</head>
<body>
<main>
  <h1>Airclone</h1>
  <p class="sub">Sign in to reach this machine's remotes.</p>
  $errorBlock
  $noticeBlock
  <form id="f">
    <label for="u">Username</label>
    <input id="u" name="username" autocomplete="username" autofocus required>
    <label for="p">Password</label>
    <input id="p" name="password" type="password" autocomplete="current-password" required>
    <button id="b" type="submit">Sign in</button>
  </form>
  <noscript><p class="msg error">JavaScript is required to sign in.</p></noscript>
  <footer>The password was generated on first launch. It is in
  <code>webui.env</code> beside your rclone config.</footer>
</main>
<script nonce="${_escape(nonce)}">
// Submitted with fetch and a custom header so the server can require that
// header on every state-changing request; a cross-origin form cannot set one.
const f = document.getElementById('f');
const b = document.getElementById('b');
f.addEventListener('submit', async (e) => {
  e.preventDefault();
  b.disabled = true;
  try {
    const r = await fetch('/api/login', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'X-Airclone-WebUI': '1' },
      body: JSON.stringify({
        username: document.getElementById('u').value,
        password: document.getElementById('p').value,
      }),
      credentials: 'same-origin',
    });
    if (r.ok) { window.location.replace('/'); return; }
    const body = await r.json().catch(() => ({}));
    render(body.error || 'Sign in failed.');
  } catch (err) {
    render('Could not reach the server.');
  }
  b.disabled = false;
});
function render(message) {
  let el = document.querySelector('.msg.error');
  if (!el) {
    el = document.createElement('p');
    el.className = 'msg error';
    el.setAttribute('role', 'alert');
    f.parentNode.insertBefore(el, f);
  }
  el.textContent = message;
}
</script>
</body>
</html>
''';
}

/// Escapes text interpolated into the page.
///
/// The only untrusted-ish input here is a throttle message built from a
/// duration, but escaping is unconditional: the moment someone interpolates a
/// username or a path into this page, the safe thing must already be the
/// default.
String _escape(String s) => const HtmlEscape().convert(s);
