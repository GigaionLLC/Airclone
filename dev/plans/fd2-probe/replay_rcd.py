#!/usr/bin/env python3
"""Re-walk the config flows on an rclone binary and rewrite the app fixtures.

The Linux way to do what capture_flow.dart and dump_providers.dart do on
Windows: same walks, same answers, through `rclone rcd` on a scratch config.
A walk stops before any state that would bind the OAuth listener.

    replay_rcd.py <rclone binary> <version, e.g. v1.76.0> <fixture dir>
"""
import json
import pathlib
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request

PORT = 15672
FLOWS = {
    "drive_declines_shared_id": ("drive", {"config_shared_client_id": "false"}),
    "drive_accepts_shared_id": ("drive", {"config_shared_client_id": "true"}),
    "googlephotos_declines_shared_id": (
        "google photos", {"config_shared_client_id": "false"}),
    "googlecloudstorage": ("google cloud storage", {}),
    "dropbox": ("dropbox", {}),
    "onedrive": ("onedrive", {}),
    "b2_asks_nothing": ("b2", {}),
    "sftp_asks_nothing": ("sftp", {}),
}
OPTION_KEYS = ("Name", "Type", "Required", "IsPassword", "Sensitive", "Advanced",
               "Hide", "Provider", "Exclusive")


def call(method, body):
    req = urllib.request.Request(
        f"http://127.0.0.1:{PORT}/{method}", json.dumps(body).encode(),
        {"Content-Type": "application/json"})
    try:
        return json.load(urllib.request.urlopen(req, timeout=30))
    except urllib.error.HTTPError as e:
        return json.load(e)


def walk(backend, answers):
    name = "capture"
    res = call("config/create", {
        "name": name, "type": backend, "parameters": {},
        "opt": {"nonInteractive": True, "obscure": True}})
    steps = [{"call": "create", "result": res}]
    for _ in range(8):
        state = res.get("State") or ""
        option = res.get("Option")
        if not state or not option or state.startswith("*oauth"):
            break
        answer = answers.get(option.get("Name") or "")
        if answer is None:
            break
        res = call("config/create", {
            "name": name, "type": backend, "parameters": {},
            "opt": {"nonInteractive": True, "continue": True,
                    "state": state, "result": answer}})
        steps.append({"call": "continue", "answered": option["Name"],
                      "with": answer, "result": res})
    call("config/delete", {"name": name})
    return {"type": backend, "steps": steps}


def trimmed(provider):
    return {
        "Description": provider["Description"],
        "Options": [
            {**{k: o.get(k) for k in OPTION_KEYS},
             "Provider": o.get("Provider") or "",
             "ExampleCount": len(o.get("Examples") or [])}
            for o in provider["Options"]
        ],
    }


def provider_json(doc):
    """One option per line, as the fixture has always been laid out."""
    head = {k: v for k, v in doc.items() if k != "providers"}
    lines = [json.dumps(head, indent=1, ensure_ascii=False)[:-2] + ",",
             ' "providers": {']
    names = list(doc["providers"])
    for name in names:
        p = doc["providers"][name]
        lines += [f"  {json.dumps(name)}: {{",
                  f'   "Description": {json.dumps(p["Description"], ensure_ascii=False)},',
                  '   "Options": [']
        rows = [json.dumps(o, ensure_ascii=False) for o in p["Options"]]
        lines += [f"    {r}," for r in rows[:-1]] + [f"    {rows[-1]}"]
        lines += ["   ]", "  }," if name != names[-1] else "  }"]
    return "\n".join(lines + [" }", "}"])


def main():
    binary, version, out = sys.argv[1], sys.argv[2], pathlib.Path(sys.argv[3])
    with tempfile.TemporaryDirectory() as scratch:
        engine = subprocess.Popen(
            [binary, "rcd", "--rc-no-auth", f"--rc-addr=127.0.0.1:{PORT}",
             "--config", f"{scratch}/capture.conf"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            for _ in range(50):
                try:
                    call("rc/noop", {})
                    break
                except OSError:
                    time.sleep(0.1)
            flows = {k: walk(*v) for k, v in FLOWS.items()}
            providers = {p["Name"]: p for p in call("config/providers", {})["providers"]}
        finally:
            engine.terminate()
            engine.wait()

    path = out / "interactive_flows.json"
    doc = json.loads(path.read_text(encoding="utf-8"))
    doc.update(
        _source=f"Captured from rclone {version} through rclone rcd by "
                "dev/plans/fd2-probe/replay_rcd.py. Walks stop before any state "
                "that would bind the OAuth listener.",
        rcloneVersion=version, flows=flows)
    path.write_text(json.dumps(doc, indent=1, ensure_ascii=False), encoding="utf-8")

    path = out / "provider_options.json"
    doc = json.loads(path.read_text(encoding="utf-8"))
    doc["_source"] = doc["_source"].replace(doc["rcloneVersion"], version).replace(
        "dev/plans/fd2-probe/dump_providers.dart", "dev/plans/fd2-probe/replay_rcd.py")
    doc["rcloneVersion"] = version
    doc["providers"] = {k: trimmed(providers[k]) for k in doc["providers"]}
    path.write_text(provider_json(doc), encoding="utf-8")


if __name__ == "__main__":
    main()
