// The btw desktop preview: an Omarchy-style session in the browser.
// The bar stands in for waybar, the app menu for walker, the tiling for
// Hyprland and the terminal for Alacritty, so the real desktop and this
// preview can share one theme (see theme.css and distro/themes/fractal/).
(function () {
  "use strict";

  const $ = (id) => document.getElementById(id);
  const WORKSPACES = 5;
  const started = Date.now();

  // ---------- helpers ----------

  function el(tag, attrs, ...children) {
    const node = document.createElement(tag);
    for (const [key, value] of Object.entries(attrs || {})) {
      if (key === "class") node.className = value;
      else if (key === "html") node.innerHTML = value;
      else if (key.startsWith("on")) node.addEventListener(key.slice(2), value);
      else if (value !== false && value != null) node.setAttribute(key, value === true ? "" : value);
    }
    for (const child of children.flat()) {
      if (child != null) node.append(child.nodeType ? child : document.createTextNode(String(child)));
    }
    return node;
  }

  function escapeHTML(text) {
    return String(text).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
  }

  const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

  function storage(key, fallback) {
    try {
      const value = localStorage.getItem(key);
      return value == null ? fallback : value;
    } catch {
      return fallback;
    }
  }

  function store(key, value) {
    try {
      localStorage.setItem(key, value);
    } catch {
      /* private mode or blocked storage: notes just won't persist */
    }
  }

  // ---------- icons ----------

  const ICON_PATHS = {
    terminal: '<rect x="3" y="4" width="18" height="16" rx="2.5"/><path d="M7 9l3 3-3 3M12.5 15H17"/>',
    fractals: '<path d="M12 3l9 16H3z"/><path d="M7.5 11h9M12 19l-4.5-8M12 19l4.5-8"/>',
    files: '<path d="M3 7.5A2.5 2.5 0 0 1 5.5 5H10l2 2h6.5A2.5 2.5 0 0 1 21 9.5v8a2.5 2.5 0 0 1-2.5 2.5h-13A2.5 2.5 0 0 1 3 17.5z"/>',
    file: '<path d="M7 3h7l5 5v11.5A1.5 1.5 0 0 1 17.5 21h-10.5A1.5 1.5 0 0 1 5.5 19.5V4.5A1.5 1.5 0 0 1 7 3z"/><path d="M14 3v5h5"/>',
    monitor: '<path d="M3 12h4l2.5-6 5 12 2.5-6h4"/>',
    notes: '<path d="M6 3h9l4 4v12.5a1.5 1.5 0 0 1-1.5 1.5h-11A1.5 1.5 0 0 1 5 19.5v-15A1.5 1.5 0 0 1 6 3z"/><path d="M9 11h6M9 15h6M9 7h3"/>',
    about: '<circle cx="12" cy="12" r="9"/><path d="M12 11v6M12 7.5v.5"/>',
    lock: '<rect x="5" y="10.5" width="14" height="10" rx="2"/><path d="M8 10.5V8a4 4 0 0 1 8 0v2.5"/>',
    restart: '<path d="M20 12a8 8 0 1 1-2.34-5.66M20 4v5h-5"/>',
    power: '<path d="M12 3v8M6.4 6.6a8 8 0 1 0 11.2 0"/>',
    cpu: '<rect x="6" y="6" width="12" height="12" rx="2"/><path d="M10 10h4v4h-4zM9 3v3M15 3v3M9 18v3M15 18v3M3 9h3M3 15h3M18 9h3M18 15h3"/>',
    memory: '<rect x="3" y="7" width="18" height="10" rx="1.5"/><path d="M7 7v10M11 7v10M15 7v10"/>',
    network: '<path d="M4 9.5a12 12 0 0 1 16 0M7 13a7.5 7.5 0 0 1 10 0M10 16.5a3 3 0 0 1 4 0"/><circle cx="12" cy="19.5" r=".6"/>',
    search: '<circle cx="11" cy="11" r="6.5"/><path d="M20 20l-4.2-4.2"/>',
  };

  function icon(name) {
    return `<svg class="icon" viewBox="0 0 24 24" aria-hidden="true">${ICON_PATHS[name] || ""}</svg>`;
  }

  // The btw mark: a Sierpinski triangle, mint at the top fading to amber.
  let logoCount = 0;
  function logo(depth = 4) {
    const id = `btw-grad-${++logoCount}`;
    const tris = [];
    (function split(x, y, size, d) {
      if (d === 0) {
        const h = size * 0.866;
        tris.push(`M${x.toFixed(2)} ${y.toFixed(2)}l${(size / 2).toFixed(2)} ${h.toFixed(2)}h${(-size).toFixed(2)}z`);
        return;
      }
      const half = size / 2;
      const h = half * 0.866;
      split(x, y, half, d - 1);
      split(x - half / 2, y + h, half, d - 1);
      split(x + half / 2, y + h, half, d - 1);
    })(12, 2.5, 19, depth);
    return (
      `<svg viewBox="0 0 24 21" aria-hidden="true"><defs><linearGradient id="${id}" x1="0" y1="0" x2="0" y2="1">` +
      `<stop offset="0" stop-color="var(--accent)"/><stop offset="1" stop-color="var(--amber)"/></linearGradient></defs>` +
      `<path fill="url(#${id})" d="${tris.join("")}"/></svg>`
    );
  }

  // ---------- system stats (shared by the bar, monitor and fastfetch) ----------

  const cores = Math.min(Math.max(navigator.hardwareConcurrency || 4, 2), 8);
  const stats = {
    cpu: Array.from({ length: cores }, () => 6 + Math.random() * 10),
    memUsed: 1.3,
    memTotal: 4,
  };

  function tickStats() {
    const busy = Object.keys(windows).length;
    stats.cpu = stats.cpu.map((v) => {
      const target = 5 + busy * 3 + (Wallpaper.state.speed > 0 ? 12 : 0);
      return Math.min(98, Math.max(1, v + (target - v) * 0.25 + (Math.random() - 0.5) * 14));
    });
    stats.memUsed = Math.min(stats.memTotal - 0.4, 1.05 + busy * 0.11 + Math.random() * 0.06);
  }

  const cpuAverage = () => stats.cpu.reduce((a, b) => a + b, 0) / stats.cpu.length;

  function uptime() {
    const minutes = Math.floor((Date.now() - started) / 60000);
    return minutes < 1 ? "less than a minute" : minutes === 1 ? "1 min" : `${minutes} mins`;
  }

  // ---------- window manager (Hyprland-style master/stack tiling) ----------

  const tiles = $("tiles");
  const windows = {};
  const order = {}; // workspace -> [window ids], master first
  let currentWs = 1;
  let focusedId = null;
  let nextId = 1;
  for (let i = 1; i <= WORKSPACES; i++) order[i] = [];

  function createWindow(appId, title) {
    const id = nextId++;
    const body = el("div", { class: "win-body" });
    const name = el("span", { class: "win-name" }, title);
    const node = el(
      "section",
      { class: "win", "data-app": appId, "aria-label": title },
      el("header", { class: "win-title", html: icon(APPS_BY_ID[appId].icon) }, name, el("button", { class: "win-close", "aria-label": `Close ${title}`, title: "Close (Super+W)", onclick: () => closeWindow(id) }, "×")),
      body,
    );
    node.addEventListener("mousedown", () => focusWindow(id));
    node.addEventListener("focusin", () => focusWindow(id));
    const win = { id, appId, title, ws: currentWs, node, body, setTitle: (t) => ((win.title = t), (name.textContent = t), renderBar()), onClose: null, focusTarget: null };
    windows[id] = win;
    order[currentWs].push(id);
    tiles.append(node);
    focusWindow(id);
    layout();
    return win;
  }

  function closeWindow(id) {
    const win = windows[id];
    if (!win) return;
    if (win.onClose) win.onClose();
    win.node.remove();
    order[win.ws] = order[win.ws].filter((w) => w !== id);
    delete windows[id];
    if (focusedId === id) {
      const rest = order[currentWs];
      focusedId = null;
      if (rest.length) focusWindow(rest[rest.length - 1]);
    }
    layout();
  }

  function focusWindow(id) {
    const win = windows[id];
    if (!win) return;
    if (focusedId !== id) {
      if (windows[focusedId]) windows[focusedId].node.classList.remove("focused");
      focusedId = id;
      win.node.classList.add("focused");
      renderBar();
    }
    if (win.focusTarget && !win.node.contains(document.activeElement)) {
      win.focusTarget.focus({ preventScroll: true });
    }
  }

  function switchWorkspace(n) {
    if (n === currentWs || n < 1 || n > WORKSPACES) return;
    currentWs = n;
    const ids = order[n];
    focusedId = null;
    for (const win of Object.values(windows)) win.node.classList.remove("focused");
    if (ids.length) focusWindow(ids[ids.length - 1]);
    layout();
  }

  function layout() {
    const gap = 10;
    const area = tiles.getBoundingClientRect();
    const W = area.width - gap * 2;
    const H = area.height - gap * 2;
    const ids = order[currentWs];
    const narrow = area.width < 720;
    const rects = [];
    if (ids.length === 1) {
      rects.push([0, 0, W, H]);
    } else if (narrow) {
      const h = (H - gap * (ids.length - 1)) / ids.length;
      ids.forEach((_, i) => rects.push([0, i * (h + gap), W, h]));
    } else if (ids.length > 1) {
      const masterW = Math.round((W - gap) * 0.56);
      rects.push([0, 0, masterW, H]);
      const stack = ids.length - 1;
      const h = (H - gap * (stack - 1)) / stack;
      for (let i = 0; i < stack; i++) rects.push([masterW + gap, i * (h + gap), W - masterW - gap, h]);
    }
    for (const win of Object.values(windows)) win.node.hidden = win.ws !== currentWs;
    ids.forEach((id, i) => {
      const [x, y, w, h] = rects[i];
      Object.assign(windows[id].node.style, { left: `${gap + x}px`, top: `${gap + y}px`, width: `${w}px`, height: `${h}px` });
    });
    renderBar();
  }

  window.addEventListener("resize", layout);

  // ---------- bar (waybar) ----------

  $("menu-logo").innerHTML = logo(3);
  $("launcher-logo").innerHTML = logo(4);

  const wsNav = $("workspaces");
  for (let i = 1; i <= WORKSPACES; i++) {
    wsNav.append(el("button", { "aria-label": `Workspace ${i}`, title: `Workspace ${i} (Super+${i})`, onclick: () => switchWorkspace(i) }, String(i)));
  }

  function renderBar() {
    [...wsNav.children].forEach((button, i) => {
      const n = i + 1;
      button.classList.toggle("active", n === currentWs);
      button.classList.toggle("occupied", order[n].length > 0);
      button.setAttribute("aria-current", n === currentWs ? "true" : "false");
    });
    const win = windows[focusedId];
    $("bar-title").textContent = win ? win.title : "";
  }

  function renderClock() {
    const now = new Date();
    $("bar-clock").textContent = now.toLocaleString(undefined, { weekday: "short", day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" });
    $("lock-clock").textContent = now.toLocaleTimeString(undefined, { hour: "2-digit", minute: "2-digit" });
    $("lock-date").textContent = now.toLocaleDateString(undefined, { weekday: "long", day: "numeric", month: "long" });
  }

  function renderStats() {
    tickStats();
    $("bar-cpu").innerHTML = `${icon("cpu")}${Math.round(cpuAverage())}%`;
    $("bar-mem").innerHTML = `${icon("memory")}${stats.memUsed.toFixed(1)}G`;
    $("bar-net").innerHTML = `${icon("network")}wired`;
  }

  renderClock();
  renderStats();
  setInterval(renderClock, 10000);
  setInterval(renderStats, 2000);

  // ---------- fake filesystem ----------

  const FS = {
    "/": {
      etc: {
        hostname: "btw\n",
        "os-release": 'NAME="btw"\nPRETTY_NAME="btw (Arch Linux ARM)"\nID=btw\nID_LIKE=arch\nBUILD_ID=rolling\nANSI_COLOR="38;2;61;220;151"\nHOME_URL="https://github.com/noisyloop/btw"\nLOGO=btw\n',
        "pacman.conf": "[options]\nHoldPkg = pacman glibc\nArchitecture = aarch64\nColor\nILoveCandy\nParallelDownloads = 5\n\n[core]\nInclude = /etc/pacman.d/mirrorlist\n\n[extra]\nInclude = /etc/pacman.d/mirrorlist\n\n[alarm]\nInclude = /etc/pacman.d/mirrorlist\n",
      },
      home: {
        btw: {
          ".bashrc": "# ~/.bashrc\n[[ $- != *i* ]] && return\nalias ls='ls --color=auto'\nPS1='[\\u@\\h \\W]\\$ '\nfastfetch\n",
          "README.txt": "Welcome to btw.\n\nOpen the app menu with Super+Space (or the btw button).\nNew terminal: Super+Enter. Close a window: Super+W.\nWorkspaces: Super+1 … Super+5.\n\nTry `fractal list` in a terminal.\n",
          Documents: {
            "todo.md": "- [x] boot a VM from Swift\n- [x] build the factory disk\n- [ ] Hyprland with the fractal theme\n- [ ] ship the dmg\n",
          },
          Pictures: {
            "mandelbox.frac": "formula = mandelbox\n",
            "mandelbulb.frac": "formula = mandelbulb\n",
            "sierpinski.frac": "formula = sierpinski\n",
            "menger.frac": "formula = menger\n",
          },
          Projects: { btw: { "Makefile": "build smoke gui image factory dmg\n" } },
        },
      },
    },
  };
  const HOME = "/home/btw";

  function resolvePath(cwd, path) {
    if (!path || path === "~") return HOME;
    let parts = path.startsWith("/") ? [] : path.startsWith("~") ? HOME.split("/").filter(Boolean) : cwd.split("/").filter(Boolean);
    for (const part of path.replace(/^~/, "").split("/")) {
      if (!part || part === ".") continue;
      if (part === "..") parts.pop();
      else parts.push(part);
    }
    return "/" + parts.join("/");
  }

  function lookup(abs) {
    let node = FS["/"];
    for (const part of abs.split("/").filter(Boolean)) {
      if (typeof node !== "object" || !(part in node)) return undefined;
      node = node[part];
    }
    return node;
  }

  const prettyPath = (abs) => (abs === HOME ? "~" : abs.startsWith(HOME + "/") ? "~" + abs.slice(HOME.length) : abs);

  // ---------- terminal (Alacritty + bash) ----------

  const PACKAGES = ["base", "linux-aarch64", "systemd", "pacman", "bash", "sudo", "openssh", "vim", "less", "hyprland", "waybar", "walker", "alacritty", "mako", "pipewire", "wireplumber", "fastfetch", "btop", "ttf-ibm-plex", "spice-vdagent", "btw-guest", "btw-themes"];

  function fetchHTML() {
    const rows = 16;
    const lines = [];
    for (let i = 0; i < rows; i++) {
      let row = " ".repeat(rows - 1 - i);
      for (let j = 0; j <= i; j++) row += (j & (i - j)) === 0 ? "▲ " : "  "; // Pascal's triangle mod 2
      const color = i < rows * 0.55 ? "c-green" : i < rows * 0.8 ? "c-cyan" : "c-yellow";
      lines.push(`<span class="${color}">${row.trimEnd()}</span>`);
    }
    const info = [
      `<span class="c-user">btw</span>@<span class="c-user">btw</span>`,
      `<span class="c-muted">${"─".repeat(15)}</span>`,
      ["OS", "btw (Arch Linux ARM) aarch64"],
      ["Host", "Apple Virtualization (generic platform)"],
      ["Kernel", "Linux 6.17.4-1-aarch64-ARCH"],
      ["Uptime", uptime()],
      ["Packages", `${PACKAGES.length + 192} (pacman)`],
      ["Shell", "bash 5.3.3"],
      ["Display", `${window.screen.width}x${window.screen.height} (virtio-gpu)`],
      ["WM", "Hyprland (Wayland)"],
      ["Theme", "btw-fractal [mint / amber]"],
      ["Terminal", "alacritty"],
      ["CPU", `Apple M1 (${cores}) @ 3.20 GHz`],
      ["Memory", `${stats.memUsed.toFixed(2)} GiB / ${stats.memTotal.toFixed(2)} GiB`],
      ["Wallpaper", `${Wallpaper.state.formula} (live)`],
    ].map((row) => (Array.isArray(row) ? `<span class="k">${row[0]}</span>: ${escapeHTML(row[1])}` : row));
    const swatches = ["#07080a", "--ansi-red", "--ansi-green", "--ansi-yellow", "--ansi-blue", "--ansi-magenta", "--ansi-cyan", "--fg"]
      .map((c) => `<span style="background:${c.startsWith("--") ? `var(${c})` : c}"></span>`)
      .join("");
    return `<div class="fetch"><pre class="fetch-logo">${lines.join("\n")}</pre><pre class="fetch-info">${info.join("\n")}<div class="swatches">${swatches}</div></pre></div>`;
  }

  const COMMANDS = ["help", "fastfetch", "neofetch", "clear", "ls", "cd", "pwd", "cat", "echo", "whoami", "hostname", "uname", "date", "uptime", "history", "pacman", "sudo", "fractal", "open", "btw", "exit"];

  class Terminal {
    constructor(win) {
      this.win = win;
      this.root = win.body;
      this.root.classList.add("term");
      this.cwd = HOME;
      this.history = [];
      this.historyIndex = 0;
      this.busy = false;
      this.root.addEventListener("mouseup", () => {
        if (!window.getSelection().toString()) this.input?.focus({ preventScroll: true });
      });
    }

    promptHTML() {
      const dir = this.cwd === HOME ? "~" : this.cwd === "/" ? "/" : this.cwd.split("/").pop();
      return `[<span class="c-user">btw@btw</span> <span class="c-dir">${escapeHTML(dir)}</span>]$ `;
    }

    prompt() {
      const input = el("input", { class: "term-input", type: "text", "aria-label": "Terminal input", autocomplete: "off", autocapitalize: "off", spellcheck: "false" });
      const line = el("div", { class: "term-line" }, el("span", { html: this.promptHTML() }), input);
      input.addEventListener("keydown", (e) => this.onKey(e, input));
      this.root.append(line);
      this.input = input;
      this.win.focusTarget = input;
      if (focusedId === this.win.id) input.focus({ preventScroll: true });
      this.scroll();
    }

    onKey(e, input) {
      if (e.key === "Enter") {
        e.preventDefault();
        this.submit(input);
      } else if (e.key === "ArrowUp" || e.key === "ArrowDown") {
        e.preventDefault();
        if (!this.history.length) return;
        this.historyIndex = Math.min(this.history.length, Math.max(0, this.historyIndex + (e.key === "ArrowUp" ? -1 : 1)));
        input.value = this.history[this.historyIndex] || "";
      } else if (e.key === "Tab") {
        e.preventDefault();
        const word = input.value.trim();
        if (word && !word.includes(" ")) {
          const match = COMMANDS.filter((c) => c.startsWith(word));
          if (match.length === 1) input.value = match[0] + " ";
          else if (match.length > 1) this.print(match.join("  "));
        }
      } else if (e.key === "l" && e.ctrlKey) {
        e.preventDefault();
        this.clear();
        this.prompt();
      } else if (e.key === "c" && e.ctrlKey && !window.getSelection().toString()) {
        e.preventDefault();
        input.replaceWith(el("span", {}, input.value + "^C"));
        this.prompt();
      }
    }

    async submit(input) {
      const command = input.value;
      input.replaceWith(el("span", {}, command));
      this.input = null;
      if (command.trim()) {
        this.history.push(command);
      }
      this.historyIndex = this.history.length;
      this.busy = true;
      try {
        await this.run(command.trim());
      } finally {
        this.busy = false;
      }
      if (windows[this.win.id]) this.prompt();
    }

    print(text, className) {
      this.root.append(el("pre", className ? { class: className } : {}, text));
      this.scroll();
    }

    printHTML(html) {
      this.root.append(el("pre", { html }));
      this.scroll();
    }

    clear() {
      this.root.textContent = "";
    }

    scroll() {
      this.root.scrollTop = this.root.scrollHeight;
    }

    async run(line) {
      if (!line) return;
      const [cmd, ...args] = line.split(/\s+/);
      switch (cmd) {
        case "help":
          this.printHTML(
            [
              "<span class=\"c-bold\">btw preview shell</span>, with a few commands:",
              "  fastfetch           system info",
              "  ls cd pwd cat       look around (try <span class=\"c-yellow\">cat README.txt</span>)",
              "  pacman -Syu         upgrade (pacman -Q lists packages)",
              "  fractal list|NAME   change the wallpaper",
              "  open APP            open an app (terminal, fractals, files, monitor, notes, about)",
              "  clear  history  date  uptime  uname -a  whoami  exit",
            ].join("\n"),
          );
          break;
        case "fastfetch":
        case "neofetch":
          this.printHTML(fetchHTML());
          break;
        case "clear":
          this.clear();
          break;
        case "pwd":
          this.print(this.cwd);
          break;
        case "whoami":
          this.print("btw");
          break;
        case "hostname":
          this.print("btw");
          break;
        case "uname":
          this.print(args.includes("-a") ? "Linux btw 6.17.4-1-aarch64-ARCH #1 SMP PREEMPT_DYNAMIC aarch64 GNU/Linux" : "Linux");
          break;
        case "date":
          this.print(new Date().toString());
          break;
        case "uptime":
          this.print(`up ${uptime()}, 1 user, load average: ${(cpuAverage() / 50).toFixed(2)}, 0.31, 0.22`);
          break;
        case "echo":
          this.print(args.join(" ").replace(/\$USER/g, "btw").replace(/\$HOME/g, HOME).replace(/\$SHELL/g, "/bin/bash"));
          break;
        case "history":
          this.print(this.history.map((h, i) => `${String(i + 1).padStart(4)}  ${h}`).join("\n"));
          break;
        case "btw":
          this.printHTML('I use <span class="c-user">btw</span>, by the way.');
          break;
        case "ls":
          this.ls(args);
          break;
        case "cd":
          this.cd(args[0]);
          break;
        case "cat":
          this.cat(args);
          break;
        case "pacman":
          await this.pacman(args, false);
          break;
        case "sudo":
          if (args[0] === "pacman") await this.pacman(args.slice(1), true);
          else if (args.length) await this.run(args.join(" "));
          else this.print("usage: sudo command");
          break;
        case "fractal":
          this.fractal(args[0]);
          break;
        case "open": {
          const app = APPS_BY_ID[args[0]];
          if (app) app.open();
          else this.print(`open: unknown app '${args[0] || ""}' (try: ${APPS.map((a) => a.id).join(", ")})`);
          break;
        }
        case "exit":
          closeWindow(this.win.id);
          break;
        default:
          this.print(`bash: ${cmd}: command not found`);
      }
    }

    ls(args) {
      const all = args.includes("-a") || args.includes("-la") || args.includes("-al");
      const target = resolvePath(this.cwd, args.find((a) => !a.startsWith("-")));
      const node = lookup(target);
      if (node === undefined) return this.print(`ls: cannot access '${args.find((a) => !a.startsWith("-"))}': No such file or directory`);
      if (typeof node === "string") return this.print(target.split("/").pop());
      const names = Object.keys(node)
        .filter((n) => all || !n.startsWith("."))
        .sort((a, b) => a.localeCompare(b));
      this.printHTML(names.map((n) => (typeof node[n] === "object" ? `<span class="c-dir">${escapeHTML(n)}</span>` : escapeHTML(n))).join("  "));
    }

    cd(arg) {
      const target = resolvePath(this.cwd, arg);
      const node = lookup(target);
      if (node === undefined) this.print(`bash: cd: ${arg}: No such file or directory`);
      else if (typeof node === "string") this.print(`bash: cd: ${arg}: Not a directory`);
      else this.cwd = target;
    }

    cat(args) {
      if (!args.length) return this.print("cat: missing file operand");
      for (const arg of args) {
        const node = lookup(resolvePath(this.cwd, arg));
        if (node === undefined) this.print(`cat: ${arg}: No such file or directory`);
        else if (typeof node === "object") this.print(`cat: ${arg}: Is a directory`);
        else this.print(node.replace(/\n$/, ""));
      }
    }

    async pacman(args, root) {
      const op = args[0] || "";
      if (op === "-Q") return this.print(PACKAGES.map((p) => `${p} ${p.startsWith("btw") ? "0.1.0-1" : "rolling"}`).join("\n"));
      if (op.startsWith("-Q")) return this.print(`${PACKAGES.length + 192}`);
      if (!op.startsWith("-S")) return this.print("usage:  pacman <operation> [...]\ntry: pacman -Syu, pacman -Q, sudo pacman -S <package>");
      if (!root) return this.printHTML('<span class="c-red">error:</span> you cannot perform this operation unless you are root.');
      const out = (html) => this.printHTML(html);
      if (op.includes("y")) {
        out('<span class="c-blue c-bold">::</span> <span class="c-bold">Synchronizing package databases...</span>');
        for (const repo of ["core", "extra", "alarm", "btw"]) {
          await sleep(260);
          out(` ${repo.padEnd(10)} is up to date`);
        }
      }
      const targets = args.slice(1).filter((a) => !a.startsWith("-"));
      if (op.includes("u") && !targets.length) {
        await sleep(300);
        out('<span class="c-blue c-bold">::</span> <span class="c-bold">Starting full system upgrade...</span>');
        await sleep(300);
        out(" there is nothing to do");
        return;
      }
      if (!targets.length) return out('<span class="c-red">error:</span> no targets specified (use -h for help)');
      out("resolving dependencies...\nlooking for conflicting packages...\n");
      out(`<span class="c-bold">Packages (${targets.length})</span> ${targets.map((t) => `${escapeHTML(t)}-1.0-1`).join("  ")}\n`);
      out('<span class="c-blue c-bold">::</span> <span class="c-bold">Proceed with installation? [Y/n]</span> y');
      for (const t of targets) {
        const bar = el("pre", {});
        this.root.append(bar);
        for (let i = 0; i <= 20; i++) {
          // ILoveCandy: Pac-Man eats the dots.
          const eaten = "-".repeat(i);
          const left = Array.from({ length: 20 - i }, (_, k) => (k % 2 ? " " : "o")).join("");
          bar.innerHTML = ` ${escapeHTML(t).padEnd(18)} [${eaten}<span class="c-yellow">${i < 20 ? (i % 2 ? "c" : "C") : ""}</span>${left}] ${String(i * 5).padStart(3)}%`;
          this.scroll();
          await sleep(45);
        }
        if (!PACKAGES.includes(t)) PACKAGES.push(t);
      }
      out('<span class="c-blue c-bold">::</span> Running post-transaction hooks...\n(1/1) Arming ConditionNeedsUpdate...');
    }

    fractal(name) {
      if (!name || name === "list") {
        const current = Wallpaper.state.formula;
        return this.printHTML(Wallpaper.formulas.map((f) => `${f.id === current ? '<span class="c-user">*</span>' : " "} ${f.id.padEnd(11)} <span class="c-muted">${escapeHTML(f.blurb)}</span>`).join("\n"));
      }
      if (!Wallpaper.available) return this.print("fractal: this browser has no WebGL, so the wallpaper can't change");
      if (Wallpaper.setFormula(name)) this.printHTML(`wallpaper: <span class="c-user">${escapeHTML(name)}</span>`);
      else this.print(`fractal: unknown fractal '${name}' (try: fractal list)`);
    }
  }

  // ---------- apps ----------

  function openTerminal(firstCommand) {
    const win = createWindow("terminal", "btw@btw: ~");
    const term = new Terminal(win);
    if (firstCommand) {
      term.printHTML(`${term.promptHTML()}${escapeHTML(firstCommand)}`);
      term.run(firstCommand).then(() => term.prompt());
    } else {
      term.prompt();
    }
    return win;
  }

  function openFractals() {
    const existing = Object.values(windows).find((w) => w.appId === "fractals");
    if (existing) {
      if (existing.ws !== currentWs) switchWorkspace(existing.ws);
      return focusWindow(existing.id);
    }
    const win = createWindow("fractals", "Fractals");
    const root = el("div", { class: "app" });
    win.body.append(root);
    const cards = el("div", { class: "cards", role: "radiogroup", "aria-label": "Wallpaper fractal" });
    const sliders = el("div", {});
    root.append(el("h2", {}, "Fractals"), el("p", {}, Wallpaper.available ? "The wallpaper is a live, raymarched 3D fractal. Pick one and tune it." : "This browser has no WebGL, so the wallpaper is a still gradient."), cards, sliders);

    for (const f of Wallpaper.formulas) {
      cards.append(el("button", { class: "card", role: "radio", "data-id": f.id, disabled: !Wallpaper.available, onclick: () => Wallpaper.setFormula(f.id) }, el("strong", {}, f.id), el("span", {}, f.blurb)));
    }
    const controls = [
      ["hue", "Hue", 0, 1, 0.01],
      ["glow", "Glow", 0.4, 2, 0.01],
      ["speed", "Motion", 0, 3, 0.05],
    ];
    const outputs = {};
    for (const [key, label, min, max, step] of controls) {
      const id = `fr-${key}-${win.id}`;
      const input = el("input", { id, type: "range", min, max, step, disabled: !Wallpaper.available, oninput: (e) => Wallpaper.set(key, Number(e.target.value)) });
      const out = el("output", { for: id });
      outputs[key] = [input, out];
      sliders.append(el("label", { class: "slider", for: id }, el("span", {}, label), input, out));
    }
    const sync = (s) => {
      for (const card of cards.children) {
        const on = card.dataset.id === s.formula;
        card.classList.toggle("active", on);
        card.setAttribute("aria-checked", on ? "true" : "false");
      }
      for (const [key, [input, out]] of Object.entries(outputs)) {
        input.value = s[key];
        out.textContent = Number(s[key]).toFixed(2);
      }
    };
    sync(Wallpaper.state);
    win.onClose = Wallpaper.subscribe(sync);
    win.focusTarget = cards.querySelector(".card");
    return win;
  }

  function openFiles() {
    const win = createWindow("files", "Files: ~");
    const root = el("div", { class: "app" });
    win.body.append(root);
    let cwd = HOME;

    function render(selected) {
      root.textContent = "";
      win.setTitle(`Files: ${prettyPath(cwd)}`);
      const crumbs = el("div", { class: "files-path" });
      const parts = cwd.split("/").filter(Boolean);
      crumbs.append(el("button", { onclick: () => ((cwd = "/"), render()) }, "/"));
      parts.forEach((part, i) => {
        const target = "/" + parts.slice(0, i + 1).join("/");
        crumbs.append(el("button", { onclick: () => ((cwd = target), render()) }, part), i < parts.length - 1 ? "/" : "");
      });
      const grid = el("div", { class: "files-grid" });
      const node = lookup(cwd);
      const names = Object.keys(node).sort((a, b) => (typeof node[b] === "object") - (typeof node[a] === "object") || a.localeCompare(b));
      if (cwd !== "/") grid.append(el("button", { class: "file is-dir", html: icon("files"), onclick: () => ((cwd = resolvePath(cwd, "..")), render()) }, ".."));
      for (const name of names) {
        const isDir = typeof node[name] === "object";
        grid.append(
          el(
            "button",
            {
              class: `file${isDir ? " is-dir" : ""}${selected === name ? " selected" : ""}`,
              html: icon(isDir ? "files" : "file"),
              onclick: () => (isDir ? ((cwd = resolvePath(cwd, name)), render()) : render(name)),
            },
            name,
          ),
        );
      }
      root.append(crumbs, grid);
      if (selected && typeof node[selected] === "string") {
        const content = node[selected];
        const fractal = content.match(/^formula = (\w+)/);
        root.append(el("div", { class: "file-preview" }, content));
        if (fractal && Wallpaper.available) {
          root.append(el("p", { style: "margin-top:10px" }, el("button", { class: "card", onclick: () => Wallpaper.setFormula(fractal[1]) }, el("strong", {}, `Set ${fractal[1]} as wallpaper`))));
        }
      }
      win.focusTarget = grid.querySelector(".file");
    }
    render();
    return win;
  }

  function openMonitor() {
    const win = createWindow("monitor", "System Monitor");
    const root = el("div", { class: "app" });
    win.body.append(root);
    const meter = (label, value, text) =>
      el("div", { class: "meter" }, el("div", { class: "meter-head" }, el("span", {}, label), el("b", {}, text)), el("div", { class: "meter-track" }, el("div", { class: "meter-fill", style: `width:${Math.max(1, Math.min(100, value)).toFixed(1)}%` })));

    function render() {
      root.textContent = "";
      root.append(el("h2", {}, "System Monitor"));
      stats.cpu.forEach((v, i) => root.append(meter(`cpu${i}`, v, `${v.toFixed(0)}%`)));
      root.append(meter("memory", (stats.memUsed / stats.memTotal) * 100, `${stats.memUsed.toFixed(2)} / ${stats.memTotal.toFixed(1)} GiB`));
      const procs = [
        ["Hyprland", 2.1 + Math.random() * 2, 164],
        ["wallpaper (gpu)", Wallpaper.state.speed > 0 ? 9 + Math.random() * 6 : 0.2, 88],
        ["alacritty", Object.values(windows).filter((w) => w.appId === "terminal").length * (0.4 + Math.random()), 61],
        ["waybar", 0.3 + Math.random() * 0.4, 42],
        ["pipewire", 0.2 + Math.random() * 0.3, 18],
        ["spice-vdagent", 0.1, 7],
      ].sort((a, b) => b[1] - a[1]);
      root.append(
        el(
          "table",
          { class: "procs" },
          el("thead", {}, el("tr", {}, el("th", {}, "process"), el("th", {}, "cpu%"), el("th", {}, "mem MiB"))),
          el("tbody", {}, procs.map(([n, c, m]) => el("tr", {}, el("td", {}, n), el("td", {}, c.toFixed(1)), el("td", {}, String(m))))),
        ),
      );
    }
    render();
    const timer = setInterval(render, 2000);
    win.onClose = () => clearInterval(timer);
    return win;
  }

  function openNotes() {
    const win = createWindow("notes", "Notes");
    const area = el("textarea", { class: "notes", "aria-label": "Notes", spellcheck: "false", placeholder: "Write something. It stays in this browser." });
    area.value = storage("btw-notes", "");
    area.addEventListener("input", () => store("btw-notes", area.value));
    win.body.append(area);
    win.focusTarget = area;
    area.focus();
    return win;
  }

  function openAbout() {
    const win = createWindow("about", "About btw");
    win.body.append(
      el(
        "div",
        { class: "about", html: logo(5) },
        el("h2", {}, "btw"),
        el("p", { html: "Arch Linux ARM with a fractal soul, made to boot on your Mac." }),
        el("p", { html: "This is a <b>preview</b> of the desktop running in your browser. The real one is Hyprland in a VM, themed from the same palette (<code>distro/themes/fractal</code>)." }),
      ),
    );
    return win;
  }

  // ---------- power ----------

  function lock() {
    const overlay = $("lock");
    overlay.hidden = false;
    overlay.focus();
    const unlock = () => {
      overlay.hidden = true;
      overlay.removeEventListener("click", unlock);
      overlay.removeEventListener("keydown", unlock);
      if (windows[focusedId]) focusWindow(focusedId);
    };
    overlay.addEventListener("click", unlock);
    overlay.addEventListener("keydown", unlock);
  }

  async function powerSequence(lines, finalHTML) {
    const overlay = $("power");
    overlay.textContent = "";
    overlay.hidden = false;
    const fast = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    for (const line of lines) {
      overlay.append(el("div", { html: line }));
      await sleep(fast ? 0 : 90 + Math.random() * 90);
    }
    if (finalHTML) overlay.append(el("div", { class: "wake", html: finalHTML }));
    return overlay;
  }

  const ok = (text) => `[  <span class="ok">OK</span>  ] ${text}`;

  async function boot(skipLog) {
    if (!skipLog) {
      await powerSequence([
        "systemd-boot: booting btw (linux-aarch64)",
        ok("Started Journal Service."),
        ok("Reached target Local File Systems."),
        ok("Finished Repartition Root Disk."),
        ok("Started Network Configuration."),
        ok("Started Network Name Resolution."),
        ok("Reached target Graphical Interface."),
        ok("Started Hyprland on tty1."),
      ]);
      await sleep(250);
    }
    $("power").hidden = true;
    openTerminal("fastfetch");
  }

  async function shutdown(restart) {
    closeLauncher();
    for (const id of Object.keys(windows)) closeWindow(Number(id));
    const overlay = await powerSequence(
      [ok("Stopped Hyprland on tty1."), ok("Stopped Network Name Resolution."), ok("Unmounted /boot."), ok("Reached target System Power Off."), restart ? "reboot: Restarting system" : "reboot: Power down"],
      restart ? null : "Powered off. Click or press any key to boot btw.",
    );
    for (let i = 1; i <= WORKSPACES; i++) order[i] = [];
    currentWs = 1;
    if (restart) {
      await sleep(400);
      return boot();
    }
    const wake = () => {
      overlay.removeEventListener("click", wake);
      document.removeEventListener("keydown", wake);
      boot();
    };
    overlay.addEventListener("click", wake);
    document.addEventListener("keydown", wake);
  }

  // ---------- launcher (walker) ----------

  const APPS = [
    { id: "terminal", name: "Terminal", desc: "Alacritty with bash", cat: "System", icon: "terminal", keys: "Super+Enter", open: () => openTerminal() },
    { id: "fractals", name: "Fractals", desc: "Choose and tune the live wallpaper", cat: "Graphics", icon: "fractals", open: openFractals },
    { id: "files", name: "Files", desc: "Browse your home folder", cat: "System", icon: "files", open: openFiles },
    { id: "monitor", name: "System Monitor", desc: "CPU, memory and processes", cat: "System", icon: "monitor", open: openMonitor },
    { id: "notes", name: "Notes", desc: "A scratchpad that remembers", cat: "Office", icon: "notes", open: openNotes },
    { id: "about", name: "About btw", desc: "What this is", cat: "System", icon: "about", open: openAbout },
    { id: "lock", name: "Lock", desc: "Lock the screen", cat: "Power", icon: "lock", power: true, open: lock },
    { id: "restart", name: "Restart", desc: "Reboot btw", cat: "Power", icon: "restart", power: true, open: () => shutdown(true) },
    { id: "shutdown", name: "Shut down", desc: "Power off btw", cat: "Power", icon: "power", power: true, open: () => shutdown(false) },
  ];
  const APPS_BY_ID = Object.fromEntries(APPS.map((a) => [a.id, a]));
  const CATEGORIES = ["All", "System", "Graphics", "Office", "Power"];

  const launcher = $("launcher");
  const search = $("launcher-search");
  const list = $("launcher-list");
  const cats = $("launcher-cats");
  const menuButton = $("menu-button");
  let category = "All";
  let results = [];
  let selected = 0;
  let returnFocus = null;

  for (const c of CATEGORIES) {
    cats.append(el("button", { role: "tab", "data-cat": c, onclick: () => ((category = c), renderLauncher(), search.focus()) }, c));
  }

  function renderLauncher() {
    const q = search.value.trim().toLowerCase();
    results = APPS.filter((a) => (category === "All" || a.cat === category) && (!q || `${a.name} ${a.desc} ${a.id}`.toLowerCase().includes(q)));
    if (!q && category === "All") results.sort((a, b) => Number(Boolean(a.power)) - Number(Boolean(b.power)));
    selected = Math.min(selected, Math.max(0, results.length - 1));
    for (const b of cats.children) {
      const on = b.dataset.cat === category;
      b.classList.toggle("active", on);
      b.setAttribute("aria-selected", on ? "true" : "false");
    }
    list.textContent = "";
    if (!results.length) {
      list.append(el("li", { class: "launcher-empty" }, `Nothing matches “${search.value}”.`));
      search.removeAttribute("aria-activedescendant");
      return;
    }
    let section = null;
    results.forEach((app, i) => {
      const group = app.power ? "Power" : "Apps";
      if (group !== section && (category === "All" || q)) {
        section = group;
        list.append(el("li", { class: "launcher-section", role: "presentation" }, group));
      }
      list.append(
        el(
          "li",
          {
            class: `launcher-item${app.power ? " power" : ""}`,
            id: `launch-${app.id}`,
            role: "option",
            "aria-selected": i === selected ? "true" : "false",
            onclick: () => launch(app),
            onmousemove: () => {
              if (selected !== i) ((selected = i), renderLauncher());
            },
          },
          el("span", { class: "glyph", html: icon(app.icon) }),
          el("span", {}, el("div", { class: "name" }, app.name), el("div", { class: "desc" }, app.desc)),
          app.keys ? el("kbd", {}, app.keys) : null,
        ),
      );
    });
    search.setAttribute("aria-activedescendant", `launch-${results[selected].id}`);
    document.getElementById(`launch-${results[selected].id}`)?.scrollIntoView({ block: "nearest" });
  }

  function openLauncher() {
    if (!launcher.hidden) return;
    returnFocus = document.activeElement;
    launcher.hidden = false;
    menuButton.setAttribute("aria-expanded", "true");
    search.value = "";
    category = "All";
    selected = 0;
    renderLauncher();
    search.focus();
  }

  function closeLauncher() {
    if (launcher.hidden) return;
    launcher.hidden = true;
    menuButton.setAttribute("aria-expanded", "false");
    if (returnFocus && document.contains(returnFocus)) returnFocus.focus({ preventScroll: true });
  }

  function launch(app) {
    returnFocus = null;
    closeLauncher();
    app.open();
  }

  menuButton.addEventListener("click", () => (launcher.hidden ? openLauncher() : closeLauncher()));
  launcher.addEventListener("mousedown", (e) => {
    if (e.target === launcher) closeLauncher();
  });
  search.addEventListener("input", () => ((selected = 0), renderLauncher()));
  search.addEventListener("keydown", (e) => {
    if (e.key === "ArrowDown" || e.key === "ArrowUp") {
      e.preventDefault();
      if (results.length) selected = (selected + (e.key === "ArrowDown" ? 1 : -1) + results.length) % results.length;
      renderLauncher();
    } else if (e.key === "Enter") {
      e.preventDefault();
      if (results[selected]) launch(results[selected]);
    } else if (e.key === "Tab") {
      e.preventDefault();
      const i = CATEGORIES.indexOf(category);
      category = CATEGORIES[(i + (e.shiftKey ? CATEGORIES.length - 1 : 1)) % CATEGORIES.length];
      selected = 0;
      renderLauncher();
    }
  });

  // ---------- keybindings (Omarchy-style; Alt works where the OS keeps Super) ----------

  document.addEventListener("keydown", (e) => {
    if (!$("power").hidden || !$("lock").hidden) return;
    if (e.key === "Escape" && !launcher.hidden) {
      e.preventDefault();
      return closeLauncher();
    }
    const mod = e.metaKey || e.altKey;
    if (!mod && !(e.ctrlKey && e.code === "Space")) return;
    if (e.code === "Space") {
      e.preventDefault();
      launcher.hidden ? openLauncher() : closeLauncher();
    } else if (!mod) {
      return;
    } else if (e.key === "Enter") {
      e.preventDefault();
      closeLauncher();
      openTerminal();
    } else if (e.code === "KeyW") {
      e.preventDefault();
      closeWindow(focusedId);
    } else if (/^Digit[1-5]$/.test(e.code)) {
      e.preventDefault();
      closeLauncher();
      switchWorkspace(Number(e.code.slice(5)));
    } else if (e.code === "KeyL" && e.shiftKey) {
      e.preventDefault();
      lock();
    }
  });

  // ---------- start ----------

  const skipBoot = window.matchMedia("(prefers-reduced-motion: reduce)").matches || new URLSearchParams(location.search).has("noboot");
  boot(skipBoot);
})();
