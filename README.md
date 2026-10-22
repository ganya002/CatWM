<p align="center">
  <img src="website/public/icon.png" width="96" alt="CatWM app icon">
</p>

<h1 align="center">CatWM</h1>

<p align="center">A simple, modern, and fast tiling window manager for macOS.</p>

<p align="center">
  <a href="https://catwm.perwko.com"><img src="website/public/demo-poster.jpg" width="760" alt="CatWM tiles a Finder window and two terminal windows side by side"></a>
</p>

## Install

```sh
curl -fsSL https://catwm.perwko.com/install.sh | sh -s -- --beta
```

## How to use ouch

The central concept of ouch is "Window mode", think of it as Vim's visual mode, the build mode in a game, or the tool keys in a drawing app. You enter it with `⌘ + tab`. This is where you can move windows, displays, change layouts and more.

Here is a overview of what key binds are available within window mode. (This is openable by pressing `?` within window mode)

<p align="center">
  <img src="docs/assets/readme/window-mode-keys.png" width="760" alt="The keys available in window mode">
  <img src="docs/assets/readme/window-mode-keys-shift.png" width="760" alt="The keys available in window mode while shift is held">
</p>

### Workspaces

Unlike all the other macOS tilers I've ever seen, ouch uses native spaces. This works well because ouch uses SkyLight, the private macOS interface that Mission Control uses. It lets ouch create and switch Desktops and move windows between them.

<p align="center">
  <img src="docs/assets/readme/workspaces.webp" width="760" alt="Switching macOS Desktops with ouch workspaces">
</p>

### Layouts

Every workspace has its own layout. Press `p` or `n` in window mode to cycle through them: tall, wide, columns, two pane, binary space partitioning, floating and more.

<p align="center">
  <img src="docs/assets/readme/layouts.webp" width="760" alt="Cycling through layouts in window mode">
</p>

### Save workspaces

Quickly save and open workspaces, including some of the apps state.

<p align="center">
  <img src="docs/assets/readme/templates.webp" width="760" alt="Saving and opening a workspace template">
</p>
<sub>We are currently working on adding adapters to save more app states, in this example you can see that we restore the active tab in helium. And that is the limit with chromium browsers for now.</sub>

### Overview

Reorder your windows without dealing with the native macOS fuss.

<p align="center">
  <img src="docs/assets/readme/overview.webp" width="760" alt="Reordering windows in the overview">
</p>

### Callable via cli

Agents (and humans) can call ouch via cli. Every bind is a dispatcher, and the cli runs the same ones.

```sh
ouch dispatch workspace 2
ouch dispatch movefocus l
```

<sub>We do not plan to add full support if any for urls (ouch://), if we do this anyone can close windows and etc.</sub>

## Contributing

Thank you for being interested in my project!
Please read [CONTRIBUTING.md](CONTRIBUTING.md).
