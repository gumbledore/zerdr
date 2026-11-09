// zerdr: alt-z opens the focused pane's git root in Zed; alt-shift-z opens the latest commit in Zed.
// keys.json: "alt-z": "zerdr.open", "alt-shift-z": "zerdr.review"

import { View, div } from "gpui-kit";
import { notify, exec, focused, spaces, nextCommand } from "herdr";

async function open(commit) {
  const f = focused();
  if (!f?.cwd) return notify({ title: "Zed", body: "No folder in the focused pane.", level: "warning" });
  if (spaces().find((s) => s.id === f.space)?.machine)
    return notify({ title: "Zed", body: "Remote pane: Zed opens local folders only.", level: "warning" });
  const top = await exec("git", ["rev-parse", "--show-toplevel"], { cwd: f.cwd });
  const root = top.code === 0 ? top.stdout.trim() : "";
  if (!root) return notify({ title: "Zed", body: `Not a git repo: ${f.cwd}`, level: "warning" });
  let url = root;
  if (commit) {
    const h = await exec("git", ["rev-parse", "HEAD"], { cwd: root });
    if (h.code !== 0) return notify({ title: "Zed", body: "No commits yet.", level: "warning" });
    url = `zed://git/commit/${h.stdout.trim()}?repo=${encodeURIComponent(root)}`;
  }
  const r = await exec("zeditor", [url]);
  if (r.code !== 0) notify({ title: "Zed", body: (r.stderr || "zeditor failed").trim(), level: "error" });
}

export default class Zerdr extends View {
  init(_props, cx) {
    cx.spawn(async () => {
      for (;;) {
        const c = await nextCommand();
        try {
          if (c === "open") await open();
          else if (c === "review") await open(true);
        } catch (e) { notify({ title: "zerdr", body: String(e?.message ?? e), level: "error" }); }
      }
    });
  }
  render() { return div(); }
}
