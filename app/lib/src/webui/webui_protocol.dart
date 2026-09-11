/// The contract between the Web UI server and the Web UI client.
///
/// Both halves of this feature are in one codebase, which makes it tempting to
/// let the client import the server for a constant. It must not: the server is
/// built on `dart:io` and belongs only to the host, while the client is
/// compiled into the browser bundle. This file is the small, pure middle — names
/// and shapes, no behaviour — so neither side has to depend on the other.
library;

/// Name of the session cookie.
const String kSessionCookieName = 'airclone_webui_session';

/// Header a state-changing request must carry.
///
/// CSRF defence that costs nothing: a browser will not let a cross-origin form
/// or image request set a custom header, and the preflight it would need
/// instead is one this server never approves. Combined with `SameSite=Strict`
/// on the cookie it means a hostile page cannot act as a signed-in operator.
const String kWebUiCsrfHeader = 'x-airclone-webui';

/// Largest `POST /api/rc` body accepted, in bytes.
///
/// RC parameter objects are small. The cap exists so an authenticated-looking
/// socket cannot make the host buffer unbounded memory.
const int kMaxRcBodyBytes = 1024 * 1024;

/// Path of the sign-in page.
const String kLoginPath = '/login';

/// Path of the RC proxy.
const String kRcPath = '/api/rc';

/// Path of the object-bytes endpoint.
const String kObjectPath = '/api/object';

/// Path of the session probe.
const String kWhoamiPath = '/api/whoami';

/// Path that ends a session.
const String kLogoutPath = '/api/logout';

/// Path that starts one.
const String kLoginApiPath = '/api/login';
