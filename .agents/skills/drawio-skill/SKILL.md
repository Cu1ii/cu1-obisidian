---
name: drawio-skill
version: 2.0.0
description: Use when the user requests diagrams, flowcharts, architecture diagrams, ER diagrams, UML / sequence / class diagrams, network topology, ML/DL model figures (Transformer/CNN/LSTM), mind maps, or any visualization. Also use proactively when explaining systems with 3+ components, complex data flows, or relationships that benefit from visual representation. Best suited when the diagram needs custom styling, rich shape vocabulary, or swimlanes. Generates `.drawio` XML files, and — when the `drawio` CLI is available — automatically exports a sibling `.svg` alongside each `.drawio` file.
license: MIT
homepage: https://github.com/Agents365-ai/drawio-skill
compatibility: Optional dependency on the `drawio` CLI (from drawio-desktop) for automatic SVG export. Without the CLI, the skill still produces `.drawio` files that users view/export via the Obsidian drawio plugin.
platforms: [macos, linux, windows]
metadata: {"hermes":{"tags":["drawio","diagram","flowchart","architecture","visualization","uml"],"category":"design","related_skills":["mermaid","excalidraw","plantuml"]},"author":"Agents365-ai","version":"2.0.0"}
---

# Draw.io Diagrams

## Overview

Generate `.drawio` XML files. When the `drawio` CLI (from drawio-desktop) is available, the skill **automatically exports a sibling `.svg`** beside every `.drawio` it writes — see `## Auto-Export to SVG` below. Without the CLI, the skill still produces valid `.drawio` files; the user views/exports them via the **Obsidian drawio plugin**.

Iteration model: the user opens the generated file in Obsidian, gives text feedback in chat, and the agent edits the XML directly (and re-exports the SVG on every save when the CLI is present).

## Bundled resources

Read these on demand — none need to be in context up front.

| File | Read it when |
|---|---|
| `references/diagram-types.md` | The user names a specific diagram type (ERD, UML class, sequence, architecture, ML/DL, flowchart) |
| `references/style-presets.md` | The user asks to learn / save / list / set-default / delete a style preset, or you've resolved an active preset and need the application rules |
| `references/style-extraction.md` | You're inside the Learn flow and need the extraction procedure (called from `style-presets.md`) |
| `references/troubleshooting.md` | A rendering looks wrong after the user opens the file in Obsidian |

## Workflow

Before starting, assess whether the user's request is specific enough. If key details are missing, ask 1-3 focused questions:
- **Diagram type** — which preset? (ERD, UML, Sequence, Architecture, ML/DL, Flowchart, or general)
- **Output location** — default is the **`assets/` subfolder of the directory containing the current note** (see "Output path resolution" below). Honor any explicit path the user gives (e.g. `attachments/`, `notes/diagrams/`). Don't ask if they didn't mention one.
- **Scope/fidelity** — how many components? Any specific technologies or labels?

Skip clarification if the request already specifies these details or is clearly simple (e.g., "draw a flowchart of X").

### Output path resolution

Both the `.drawio` and the auto-exported `.svg` always land in the **same directory**, resolved in this order:

1. **Explicit user path** — if the user named a directory or full path in the request (e.g. "save it to `attachments/diagrams/`"), use that verbatim.
2. **Current note's `assets/` folder** *(default)* — if a `<current_note>` is in context at `<dir>/<note>.md`, write to `<dir>/assets/`. Example: current note `note/Java/jvm/ZGC/ZGC.md` → output dir `note/Java/jvm/ZGC/assets/`.
3. **Vault current working dir** — only when no current note and no explicit path was given.

`mkdir -p` the target dir before writing. The file basename should be a short kebab-case slug describing the diagram (e.g. `zgc-cycle-phases.drawio`), not the note name.

### Embedding & link syntax (GitHub-compatible standard Markdown)

Always emit **standard CommonMark / GitHub-flavored Markdown** when referring to the generated files, never Obsidian wiki-links (`[[...]]` / `![[...]]`). Obsidian still renders standard Markdown, but the reverse is not true — and notes in this vault may be pushed to GitHub / read by other Markdown tools.

**Path form** — use the **relative path from the note's directory**, not the vault-root path:
- Note at `note/Java/jvm/ZGC/ZGC.md`, asset at `note/Java/jvm/ZGC/assets/foo.svg` → relative path `assets/foo.svg`
- Don't write the full `note/Java/jvm/ZGC/assets/foo.svg` — it breaks once the note moves
- Spaces in path: URL-encode as `%20` (e.g. `assets/my%20diagram.svg`)

**Syntax cheat sheet:**

| Purpose | Use | Avoid |
|---|---|---|
| Embed SVG inline (renders as image) | `![ZGC GC cycle](assets/zgc-cycle-phases.svg)` | `![[assets/zgc-cycle-phases.svg]]` |
| Link to the `.drawio` source | `[zgc-cycle-phases.drawio](assets/zgc-cycle-phases.drawio)` | `[[assets/zgc-cycle-phases.drawio]]` |
| Embed PNG (when explicitly requested) | `![alt](assets/foo.png)` | `![[assets/foo.png]]` |

**Alt text:** always provide meaningful alt text inside `![...]` — it's required for accessibility, used by GitHub when SVG fails to load, and indexed for search. Use a short noun-phrase describing the diagram (e.g. `![ZGC colored pointer marking flow](assets/zgc-colored-pointer-marking.svg)`), not the filename.

**Step 0 — Resolve active preset.** Determine which (if any) user-defined style preset applies to this generation.

- Scan the user's message for a phrase that clearly names a style preset: "use my `<name>` style", "with my `<name>` style", "in `<name>` mode", "in the style of `<name>`". A bare `with <name>` does **not** count — "draw a diagram with redis" names a component, not a style. If a clear match is found → active preset = `<name>`.
- Else, check `~/.drawio-skill/styles/` for any file with `"default": true`. If found → active preset = that one.
- Else → no preset active; fall through to the built-in color/shape/edge conventions for the rest of the workflow.

Load the preset JSON from `~/.drawio-skill/styles/<name>.json`, falling back to `<this-skill-dir>/styles/built-in/<name>.json`. If the named preset exists in neither location, tell the user the name is unknown, list the available presets (user dir + built-in), and stop — do **not** silently fall back to defaults.

When a preset loads successfully, mention it in the first line of the reply: *"Using preset `<name>` (confidence: `<level>`)."* See `references/style-presets.md` for how the preset changes color/shape/edge/font decisions.

1. **Plan** — identify shapes, relationships, layout (LR or TB), group by tier/layer.
2. **Generate** — write the `.drawio` XML file to disk. Resolve the output dir per the "Output path resolution" rule above (default = `<current-note-dir>/assets/`); `mkdir -p` the target dir first.
3. **Layout quality gate** — before delivery, inspect the layout for: no shape-shape overlap, no edge-shape overlap, and every unavoidable edge-edge crossing uses an arc line jump (`jumpStyle=arc;jumpSize=8`). Prefer preventing crossings with spacing/waypoints first; use arc jumps only for crossings that remain necessary.
4. **Auto-export SVG** — immediately after writing the `.drawio`, run the export procedure in `## Auto-Export to SVG`. The `.svg` goes next to the `.drawio` (same dir, same basename). On failure (CLI missing or export error), continue without blocking — never delete the `.drawio` if export fails.
5. **Deliver** — link the `.drawio` source via standard Markdown, e.g. `[bar.drawio](assets/bar.drawio)`. When SVG export succeeded, also embed the SVG inline with standard Markdown image syntax: `![alt text](assets/bar.svg)` — never `![[...]]`. See "Embedding & link syntax" above for the path/alt-text rules. When export failed/skipped, tell the user to open the `.drawio` via the Obsidian drawio plugin (the plugin handles SVG/PNG/PDF export natively).

### Review Loop

After delivering the `.drawio` file:
- User opens it in Obsidian (drawio plugin) and reviews the rendering
- User provides text feedback in chat (e.g. "make the DB node green", "add an arrow from A to B", "move X above Y", "swap to top-down layout")
- Apply targeted XML edits per the table below and re-save the file
- **Re-run the SVG export** after every save (same procedure as the initial Deliver step) so the embedded `![alt](...svg)` preview stays in sync
- Re-deliver and loop until the user is satisfied

**Targeted edit rules** — for each type of feedback, apply the minimal XML change:

| User request | XML edit action |
|-------------|----------------|
| Change color of X | Find `mxCell` by `value` matching X, update `fillColor`/`strokeColor` in `style` |
| Add a new node | Append a new `mxCell` vertex with next available `id`, position near related nodes |
| Remove a node | Delete the `mxCell` vertex and any edges with matching `source`/`target` |
| Move shape X | Update `x`/`y` in the `mxGeometry` of the matching `mxCell` |
| Resize shape X | Update `width`/`height` in the `mxGeometry` of the matching `mxCell` |
| Add arrow from A to B | Append a new `mxCell` edge with `source`/`target` matching A and B ids |
| Change label text | Update the `value` attribute of the matching `mxCell` |
| Change layout direction | **Full regeneration** — rebuild XML with new orientation |

**Rules:**
- For single-element changes: edit existing XML in place — preserves layout tuning from prior iterations
- For layout-wide changes (e.g., swap LR↔TB, "start over"): regenerate full XML
- Overwrite the same `{name}.drawio` file each iteration — do not create `v1`, `v2`, `v3` files
- **Safety valve:** after 5 iteration rounds, suggest the user fine-tune directly in the Obsidian drawio editor (drag, resize, restyle) rather than continue text iteration

## Auto-Export to SVG

After writing any `.drawio` file, the agent attempts to export a sibling `.svg` at the same path (basename + `.svg`). The export is **non-blocking** — if anything fails, the `.drawio` file is still kept and delivered.

### Procedure

1. **Detect the CLI.** Run `command -v drawio` (or `where drawio` on Windows). Only if the binary exists does export proceed.
2. **Detect display (Linux only).** If on Linux and `$DISPLAY` is empty, the CLI cannot launch Electron — wrap with `xvfb-run -a` if `xvfb-run` is also on PATH. On macOS / Windows / Linux-with-display, call `drawio` directly.
3. **Export.** Run, for each generated `.drawio` file at `<path>.drawio`:

   ```bash
   drawio -x -f svg --embed-diagram -o "<path>.svg" "<path>.drawio"
   ```

   - `-x` export, `-f svg` SVG format
   - `--embed-diagram` embeds the source `.drawio` XML inside the SVG so the SVG itself can be re-opened and edited in draw.io
   - Quote paths to handle spaces

4. **Handle multi-page diagrams.** SVG is single-page. If the source has multiple `<diagram>` elements, the CLI exports the first page by default. For each additional page index `n`, also export `<path>.page-n.svg` via `-p n`.
5. **Verify.** Check the exit code and that the `.svg` exists and is non-empty. On failure, capture stderr and report it once in the chat reply (do not retry silently).

### Reference shell helper

When exporting one or many `.drawio` files in a single batch (e.g. after generating 5 diagrams), prefer a single Bash invocation over five separate ones:

```bash
export_svg() {
  local src="$1"
  local dst="${src%.drawio}.svg"
  if ! command -v drawio >/dev/null 2>&1; then
    echo "drawio CLI not found — skipping SVG export for $src" >&2
    return 0
  fi
  local runner=""
  if [ "$(uname)" = "Linux" ] && [ -z "$DISPLAY" ] && command -v xvfb-run >/dev/null 2>&1; then
    runner="xvfb-run -a"
  fi
  $runner drawio -x -f svg --embed-diagram -o "$dst" "$src"
}
```

Batch usage:

```bash
for f in path/to/dir/*.drawio; do export_svg "$f"; done
```

### When the CLI is missing

If `command -v drawio` returns nothing, tell the user **once per session**:

> SVG auto-export is disabled because the `drawio` CLI was not found. Install it with `brew install --cask drawio` (macOS) or download drawio-desktop from https://github.com/jgraph/drawio-desktop/releases (Linux/Windows). The skill will keep generating `.drawio` files — open them in Obsidian's drawio plugin to view.

Do not repeat this message on every subsequent generation in the same session.

### Why SVG (not PNG/PDF) as the default

- **Vector** — scales cleanly inside Obsidian, on Retina displays, and in exported PDFs.
- **Text-searchable** — labels remain real text, so the diagram contributes to Obsidian search.
- **Round-trippable** — with `--embed-diagram`, the SVG itself can be re-opened by drawio-desktop and edited; no separate `.drawio` lookup needed.
- **Inline-previewable in chat & notes** — `![alt](file.svg)` renders both in Obsidian and on GitHub, while a `.drawio` file does not.

If the user explicitly asks for PNG or PDF instead, swap `-f svg` for `-f png` (add `-t` for transparent background) or `-f pdf` (add `-a` for all-pages). SVG remains the default auto-export.

## Style Presets

A **style preset** is a named JSON file capturing a user's visual preferences (palette, shapes, font, edges). When active, it fully replaces the built-in color/shape conventions in this skill.

**Lookup order** when step 0 resolves a preset name:
1. `~/.drawio-skill/styles/<name>.json` — user presets (survive `git pull`)
2. `<this-skill-dir>/styles/built-in/<name>.json` — shipped built-ins (`default`, `corporate`, `handdrawn`)

Always lowercase the user-provided name before any file operation — the schema enforces lowercase.

**For everything else — Learn flow (extracting a preset from a file), management ops (list/default/delete/rename), application rules (color lookup, shape keywords, edges, fonts, extras, interaction with diagram-type presets), and validation — read `references/style-presets.md`.** It's only needed when the user invokes those flows or when an active preset must be applied to the current generation.

## Draw.io XML Structure

### File skeleton

```xml
<?xml version="1.0" encoding="UTF-8"?>
<mxfile host="drawio" version="26.0.0">
  <diagram name="Page-1">
    <mxGraphModel>
      <root>
        <mxCell id="0" />
        <mxCell id="1" parent="0" />
        <!-- user shapes start at id="2" -->
      </root>
    </mxGraphModel>
  </diagram>
</mxfile>
```

**Rules:**
- `id="0"` and `id="1"` are required root cells — never omit them
- User shapes start at `id="2"` and increment sequentially
- All shapes have `parent="1"` (unless inside a container — then use container's id)
- All text uses `html=1` in style for proper rendering
- **Never use `--` inside XML comments** — it's illegal per XML spec and causes parse errors
- Escape special characters in attribute values: `&amp;`, `&lt;`, `&gt;`, `&quot;`
- **Multi-line text in labels:** use `&#xa;` for line breaks inside `value` attributes (not literal `\n`). Example: `value="Line 1&#xa;Line 2"`

### Shape types (vertex)

| Style keyword | Use for |
|--------------|---------|
| `rounded=0` | plain rectangle (default) |
| `rounded=1` | rounded rectangle — services, modules |
| `ellipse;` | circles/ovals — start/end, databases |
| `rhombus;` | diamond — decision points |
| `shape=mxgraph.aws4.resourceIcon;` | AWS icons |
| `shape=cylinder3;` | cylinder — databases |
| `swimlane;` | group/container with title bar |

### Required properties

```xml
<!-- Rectangle / rounded box -->
<mxCell id="2" value="Label" style="rounded=1;whiteSpace=wrap;html=1;fillColor=#dae8fc;strokeColor=#6c8ebf;" vertex="1" parent="1">
  <mxGeometry x="100" y="100" width="160" height="60" as="geometry" />
</mxCell>

<!-- Cylinder (database) -->
<mxCell id="3" value="DB" style="shape=cylinder3;whiteSpace=wrap;html=1;fillColor=#f5f5f5;strokeColor=#666666;fontColor=#333333;" vertex="1" parent="1">
  <mxGeometry x="350" y="100" width="120" height="80" as="geometry" />
</mxCell>

<!-- Diamond (decision) -->
<mxCell id="4" value="Check?" style="rhombus;whiteSpace=wrap;html=1;fillColor=#fff2cc;strokeColor=#d6b656;" vertex="1" parent="1">
  <mxGeometry x="100" y="220" width="160" height="80" as="geometry" />
</mxCell>
```

### Containers and groups

For architecture diagrams with nested elements, use draw.io's parent-child containment — do **not** just place shapes on top of larger shapes.

| Type | Style | When to use |
|------|-------|-------------|
| **Group** (invisible) | `group;pointerEvents=0;` | No visual border needed, container has no connections |
| **Swimlane** (titled) | `swimlane;startSize=30;` | Container needs a visible title bar, or container itself has connections |
| **Custom container** | Add `container=1;pointerEvents=0;` to any shape | Any shape acting as a container without its own connections |

**Key rules:**
- Add `pointerEvents=0;` to container styles that should not capture connections between children
- Children set `parent="containerId"` and use coordinates **relative to the container**

```xml
<!-- Swimlane container -->
<mxCell id="svc1" value="User Service" style="swimlane;startSize=30;fillColor=#dae8fc;strokeColor=#6c8ebf;" vertex="1" parent="1">
  <mxGeometry x="100" y="100" width="300" height="200" as="geometry"/>
</mxCell>
<!-- Child inside container — coordinates relative to parent -->
<mxCell id="api1" value="REST API" style="rounded=1;whiteSpace=wrap;html=1;" vertex="1" parent="svc1">
  <mxGeometry x="20" y="40" width="120" height="60" as="geometry"/>
</mxCell>
<mxCell id="db1" value="Database" style="shape=cylinder3;whiteSpace=wrap;html=1;" vertex="1" parent="svc1">
  <mxGeometry x="160" y="40" width="120" height="60" as="geometry"/>
</mxCell>
```

### Connector (edge)

**CRITICAL:** Every edge `mxCell` must contain a `<mxGeometry relative="1" as="geometry" />` child element. Self-closing edge cells (`<mxCell ... edge="1" ... />`) are **invalid** and will not render. Always use the expanded form.

```xml
<!-- Directed arrow — always include smart routing and arc line-jump markers -->
<mxCell id="10" value="" style="edgeStyle=orthogonalEdgeStyle;rounded=1;orthogonalLoop=1;jettySize=auto;jumpStyle=arc;jumpSize=8;html=1;" edge="1" parent="1" source="2" target="3">
  <mxGeometry relative="1" as="geometry" />
</mxCell>

<!-- Arrow with label + explicit entry/exit points to control direction -->
<mxCell id="11" value="HTTP/REST" style="edgeStyle=orthogonalEdgeStyle;rounded=1;orthogonalLoop=1;jettySize=auto;jumpStyle=arc;jumpSize=8;html=1;exitX=0.5;exitY=1;exitDx=0;exitDy=0;entryX=0.5;entryY=0;entryDx=0;entryDy=0;" edge="1" parent="1" source="2" target="4">
  <mxGeometry relative="1" as="geometry" />
</mxCell>

<!-- Arrow with waypoints — use when edge must route around other shapes -->
<mxCell id="12" value="" style="edgeStyle=orthogonalEdgeStyle;rounded=1;orthogonalLoop=1;jettySize=auto;jumpStyle=arc;jumpSize=8;html=1;" edge="1" parent="1" source="3" target="5">
  <mxGeometry relative="1" as="geometry">
    <Array as="points">
      <mxPoint x="500" y="50" />
    </Array>
  </mxGeometry>
</mxCell>
```

**Edge style rules:**
- **Animated connectors:** add `flowAnimation=1;` to any edge style to show a moving dot animation along the arrow. Renders in the Obsidian drawio plugin and in SVG exports — ideal for data-flow and pipeline diagrams. Example: `style="edgeStyle=orthogonalEdgeStyle;flowAnimation=1;rounded=1;..."`
- **Always** include `orthogonalLoop=1;jettySize=auto;jumpStyle=arc;jumpSize=8` — these enable smart routing and arc line jumps for unavoidable connector crossings. Use `rounded=1` unless a diagram type or active preset intentionally sets a different connector curvature (for example `rounded=0` in a corporate style).
- First avoid connector crossings with spacing, layout, waypoints, and distributed ports. If an edge-edge crossing remains necessary, keep it visually explicit with the arc jump marker (`jumpStyle=arc;jumpSize=8`).
- Pin `exitX/exitY/entryX/entryY` on every edge when a node has 2+ connections — distributes lines across the shape perimeter
- Add `<Array as="points">` waypoints when an edge must detour around an intermediate shape
- **Leave room for arrowheads:** the final straight segment between the last bend and the target shape must be ≥20px long. If too short, the arrowhead overlaps the bend and looks broken. Fix by increasing node spacing or adding explicit waypoints

### Distributing connections on a shape

When multiple edges connect to the same shape, assign different entry/exit points to prevent stacking:

| Position | exitX/entryX | exitY/entryY | Use when |
|----------|-------------|-------------|----------|
| Top center | 0.5 | 0 | connecting to node above |
| Top-left | 0.25 | 0 | 2nd connection from top |
| Top-right | 0.75 | 0 | 3rd connection from top |
| Right center | 1 | 0.5 | connecting to node on right |
| Bottom center | 0.5 | 1 | connecting to node below |
| Left center | 0 | 0.5 | connecting to node on left |

**Rule:** if a shape has N connections on one side, space them evenly (e.g., 3 connections on bottom → exitX = 0.25, 0.5, 0.75)

### Color palette (fillColor / strokeColor)

*Used only when no preset is active (see "Style Presets" above).*

| Color name | fillColor | strokeColor | Use for |
|-----------|-----------|-------------|---------|
| Blue | `#dae8fc` | `#6c8ebf` | services, clients |
| Green | `#d5e8d4` | `#82b366` | success, databases |
| Yellow | `#fff2cc` | `#d6b656` | queues, decisions |
| Orange | `#ffe6cc` | `#d79b00` | gateways, APIs |
| Red/Pink | `#f8cecc` | `#b85450` | errors, alerts |
| Grey | `#f5f5f5` | `#666666` | external/neutral |
| Purple | `#e1d5e7` | `#9673a6` | security, auth |

### Layout tips

**Spacing — scale with complexity:**

| Diagram complexity | Nodes | Horizontal gap | Vertical gap |
|-------------------|-------|----------------|--------------|
| Simple | ≤5 | 200px | 150px |
| Medium | 6–10 | 280px | 200px |
| Complex | >10 | 350px | 250px |

**Routing corridors:** between shape rows/columns, leave an extra ~80px empty corridor where edges can route without crossing shapes. Never place a shape in a gap that edges need to traverse.

**Grid alignment:** snap all `x`, `y`, `width`, `height` values to **multiples of 10** — this ensures shapes align cleanly on draw.io's default grid and makes manual editing easier.

**General rules:**
- Plan a grid before assigning x/y coordinates — sketch node positions on paper/mentally first
- Group related nodes in the same horizontal or vertical band
- Use `swimlane` cells for logical grouping with visible borders
- Place heavily-connected "hub" nodes centrally so edges radiate outward instead of crossing
- To force straight vertical connections, pin entry/exit points explicitly on edges:
  `exitX=0.5;exitY=1;exitDx=0;exitDy=0;entryX=0.5;entryY=0;entryDx=0;entryDy=0`
- Always center-align a child node under its parent (same center x) to avoid diagonal routing
- **Event bus pattern**: place Kafka/bus nodes in the **center of the service row**, not below — services on either side can reach it with short horizontal arrows (`exitX=1` left side, `exitX=0` right side), eliminating all line crossings
- Horizontal connections (`exitX=1` or `exitX=0`) never cross vertical nodes in the same row; use them for peer-to-peer and publish connections

**Avoiding overlap and ambiguous crossings:**
- Before finalizing coordinates, trace each edge path mentally — if it must cross an unrelated shape, either move the shape or add waypoints
- For tree/hierarchical layouts: assign nodes to layers (rows), connect only between adjacent layers to minimize crossings
- For star/hub layouts: place the hub center, satellites around it — edges stay short and radial
- When an edge must span multiple rows/columns, route it along the outer corridor, not through the middle of the diagram
- If two connectors must cross after routing, ensure both connectors use `jumpStyle=arc;jumpSize=8` so the crossing is marked with an arc rather than an ambiguous X intersection

## Common Mistakes

When a rendering looks wrong after the user opens the file in Obsidian, see `references/troubleshooting.md` for a row-by-row mistake → fix table.

## Diagram Type Presets

When the user requests a specific diagram type, read `references/diagram-types.md` for the matching preset (shapes, edges, layout direction). Pick by user phrasing:

| User says | Section in `references/diagram-types.md` |
|---|---|
| "ER diagram", "schema diagram", "data model" | ERD |
| "UML class diagram", "class diagram" | UML Class |
| "sequence diagram", "interaction diagram", "lifeline" | Sequence |
| "architecture", "system diagram", "service diagram" | Architecture |
| "neural network", "model architecture", "ML diagram", "deep learning" | ML / Deep Learning Model |
| "flowchart", "decision tree", "process flow" | Flowchart |

The diagram-type preset sets **structural** style keywords. If a user style preset is also active (see `## Style Presets`), keep the structural keywords and layer color/font/edge/extras on top — read `references/style-presets.md` → "Interaction with diagram-type presets" for the merge rules.
