# Web shape builder

[Open the builder](index.html) from the repository's
[main homepage](../../../index.html). The [plugin guide](../index.html) is a
separate page. The editor is plain HTML, CSS and
JavaScript modules. Its 3D preview uses Canvas; no framework, package installation
or build step is needed to use or serve it.

## Create your own geometry

- **Custom paths:** Place vertices or draw a freehand stroke. Edit points in
  the XY, XZ or YZ plane, or enter exact 3D coordinates. Keep a path open, close
  it into an outline, or smooth its segments. Separate paths can be separate layers.
- **Polygons and primitives:** Start with an adjustable regular polygon or a
  basic 3D shape, then use position, rotation and scale to combine layers.
- **SVG and coordinates:** Import vector outlines or a set of XYZ coordinates.
  Imported geometry becomes editable project data. SVG import samples outlines;
  it does not reproduce an SVG's rendered fills, text, images or effects.
- **Formulas:** Sample mathematical curves or surfaces into geometry. Formulas
  are parsed as math, and the resulting points are stored in the project. Apply
  the normal motion controls to animate them.

In the path editor, use **Draw** to connect points and click the first point to
close an outline. Switch to **Move** to drag a vertex, or select its number and
edit X, Y and Z directly. **Insert vertex** adds a midpoint after the selected
point. Crossed edges are supported; combine separate paths to keep independent
outlines or motions. Choose **Apply path** when the drawing is ready.

Formula parameters `u` and `v` range from 0 to 1; angles use radians. For example,
`X = 60 * (u - 0.5)`, `Y = 15 * sin(tau * u)`, `Z = 0` creates a wave-shaped
curve. For a surface, use `Z = 40 * (v - 0.5)`. A curve or surface can contain up
to 4,096 sampled points, and each expression accepts up to 500 characters.

Preview the result as debris, then adjust each layer's spin, orbit, bob, pulse,
waves, twist, taper and scatter. Bind numeric properties to sliders, add
visibility or fill switches, or use action buttons to restart, reverse and reset
a layer. Controls work in the preview and exported plugin. Undo and redo work
across project edits.

Save a JSON project to keep an editable, portable copy. Browser autosave is local
to the browser and site origin and depends on available storage. Large projects
can exceed the browser's quota; the editor will tell you to save JSON instead.
Export a `.lua` plugin, put it in your executor's
`GravityShapes` folder, and restart Project Gravity to select it by filename.

Projects support up to 64 layers, 4,096 vertices per path and 8,192 preview parts.
Project JSON imports allow up to **64 MiB**, including files saved with every
layer at its geometry limit. SVG and coordinate source imports retain a separate
**2 MB** limit. Saved projects contain the resulting geometry and do not need
the original source files to reopen.
Imported and generated coordinates must be between −5,000 and 5,000 studs.
Very detailed outlines need enough debris to remain legible. The preview samples
geometry; live Roblox physics, network ownership and available parts determine
the in-game result.

## Run locally

From the repository root:

```powershell
python -m http.server 8000 --bind 127.0.0.1
```

Open **http://127.0.0.1:8000/** for the homepage,
**http://127.0.0.1:8000/docs/plugins/builder/** for the editor, and
**http://127.0.0.1:8000/docs/plugins/** for the plugin guide. Serve the repository
root over HTTP so navigation and JavaScript modules resolve together.

For Cloudflare Pages Git integration, use framework **None**, build command
**`exit 0`**, build output directory **`.`**, and leave the root directory unset.
The hosted URLs use the same paths as the local server. See the
[hosting instructions](../../PLUGINS.md#publish-the-website).

## Folder map

| File or folder | Responsibility |
| --- | --- |
| `index.html`, `style.css` | Page structure and the shared editor layout |
| `app.mjs` | Project state, layers, property controls, undo/redo and saving |
| `project-file.mjs` | Portable JSON serialization and project file size validation |
| `model.mjs` | Project validation and formation sampling |
| `viewport.mjs` | Canvas 3D preview, camera and scene interaction |
| `exporter.mjs` | Standalone Project Gravity Lua generation |
| `geometry/path.mjs` | Custom path geometry and sampling |
| `geometry/formula.mjs` | Math expression parsing and curve/surface sampling |
| `importers/geometry.mjs` | SVG and XYZ coordinate imports |
| `editors/path-editor.mjs`, `editors/path-editor.css` | Interactive path drawing and vertex editing |
| `editors/source-editor.mjs`, `editors/source-editor.css` | Import and formula dialogs |

Browser modules use relative imports. Keep the folder structure when copying or
hosting the builder. Tests remain in the repository's `tests/` folder; see the
[repository README](../../../README.md#web-formation-builder) for the optional
Playwright setup. Playwright is a development test tool, not an editor dependency.

Run the model and import checks from the repository root:

```powershell
node tests/builder_model.test.mjs
node tests/builder_creation.test.mjs
node tests/builder_project.test.mjs
node tests/builder_controls.test.mjs
```

With the optional Playwright setup, run the browser checks:

```powershell
node tests/builder_browser.cjs
node tests/builder_path_browser.cjs
node tests/builder_import_browser.cjs
node tests/builder_project_browser.cjs
node tests/builder_controls_browser.cjs
```

These cover desktop/mobile navigation, drawing and imports, controls, exports,
and reopening large projects even when browser autosave reaches its quota.

The model and controls suites also compare generated Lua against browser behavior when
Lua, LuaJIT or Luau is available; set `LUAU` or `LUAJIT` to its executable path if
it is not on `PATH`.
