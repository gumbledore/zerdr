// zerdr: alt-z opens the focused pane's git root in Zed; alt-shift-z shows the Changes panel.
// keys.json: "alt-z": "zerdr.open", "alt-shift-z": "zerdr.review"

import { View, div } from "gpui-kit";
import { run, notify, exec, focused, spaces, nextCommand } from "herdr";

async function open() {
  const f = focused();
  if (!f?.cwd) return notify({ title: "Zed", body: "No folder in the focused pane.", level: "warning" });
  if (spaces().find((s) => s.id === f.space)?.machine)
    return notify({ title: "Zed", body: "Remote pane: Zed opens local folders only.", level: "warning" });
  const top = await exec("git", ["rev-parse", "--show-toplevel"], { cwd: f.cwd });
  const root = top.code === 0 ? top.stdout.trim() : "";
  if (!root) return notify({ title: "Zed", body: `Not a git repo: ${f.cwd}`, level: "warning" });
  const r = await exec("zeditor", [root]);
  if (r.code !== 0) notify({ title: "Zed", body: (r.stderr || "zeditor failed").trim(), level: "error" });
}

export default class Zerdr extends View {
  init(_props, cx) {
    cx.spawn(async () => {
      for (;;) {
        const c = await nextCommand();
        try {
          if (c === "open") await open();
          else if (c === "review") { run("layout.show", { id: "panel" }); run("layout.select", { stack: "panel-body", child: "changes" }); }
        } catch (e) { notify({ title: "zerdr", body: String(e?.message ?? e), level: "error" }); }
      }
    });
  }
  render() { return div(); }
}
