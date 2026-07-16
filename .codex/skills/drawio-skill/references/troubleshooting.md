# Troubleshooting — Common Mistakes

Read this when something looks wrong in the output (rendering, layout, edges) after opening the `.drawio` file in the Obsidian drawio plugin. Most rows have a one-line fix.

| Mistake | Fix |
|---------|-----|
| Missing `id="0"` and `id="1"` root cells | Always include both at the top of `<root>` |
| Shapes not connected | `source` and `target` on edge must match existing shape `id` values |
| Self-closing edge `mxCell` (`<mxCell ... edge="1" />`) | Use the expanded form with `<mxGeometry relative="1" as="geometry" />` child — self-closing edges won't render |
| `--` inside XML comments | Illegal per XML spec — use single hyphens or rephrase |
| Special characters in `value` | Use XML entities: `&amp;` `&lt;` `&gt;` `&quot;` |
| Literal `\n` in label text | Use `&#xa;` for line breaks in `value` attributes |
| Overlapping shapes | Scale spacing with complexity (200–350px); leave routing corridors |
| Edges crossing through shapes | Add waypoints, distribute entry/exit points, or increase spacing; never route through unrelated shapes |
| Unavoidable edge-edge crossings look ambiguous | Ensure connector styles include `jumpStyle=arc;jumpSize=8` so crossings render as arc line jumps |
| Arrowhead overlaps bend | Final edge segment before target must be ≥20px — increase spacing or add waypoints |
| Iteration loop never ends | After 5 rounds, suggest the user fine-tune directly in the Obsidian drawio editor (drag, resize, restyle) rather than continue text iteration |
