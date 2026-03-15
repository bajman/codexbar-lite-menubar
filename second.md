# Apple Materials, Layout, Color, and Liquid Glass APIs (Comprehensive Consolidation)

## Capture metadata
- Capture date (UTC): 2026-02-28
- Input scope: exactly the seven URLs provided
- Format: clean, structured Markdown with section-level coverage of each source page
- Note: this document is a comprehensive restatement and organization of the source material

## Source URLs
- https://developer.apple.com/design/human-interface-guidelines/materials
- https://developer.apple.com/design/human-interface-guidelines/layout
- https://developer.apple.com/design/human-interface-guidelines/color
- https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views
- https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:)
- https://developer.apple.com/documentation/swiftui/glasseffectcontainer
- https://developer.apple.com/documentation/SwiftUI/Landmarks-Building-an-app-with-Liquid-Glass

---

## 1) HIG: Materials
Source: https://developer.apple.com/design/human-interface-guidelines/materials

### Core definition
- Materials are visual layers that create depth and hierarchy between foreground and background.
- Apple distinguishes two classes:
- Liquid Glass: dynamic functional chrome/navigation layer.
- Standard materials: content-layer differentiation and structure.

### Discussion highlights
- Materials preserve context by letting background influence foreground.
- The goal is legible controls with visible content continuity.

### Liquid Glass guidance
- Treat Liquid Glass as a dedicated functional plane for controls/navigation.
- Do not generally use Liquid Glass in the content layer.
- Exception: transient interaction states for some controls in content (for example sliders/toggles during active interaction).
- Use custom Liquid Glass effects sparingly; overuse competes with content and hurts hierarchy.
- Two variants for custom use:
- `regular`: adaptive blur/luminance tuning for legibility; default for text-heavy or structurally important surfaces.
- `clear`: high translucency for media-rich backgrounds; use only when background richness should remain dominant.
- For clear variant, apply a dimming layer when background brightness would otherwise reduce contrast.
- Guidance references a dark dimmer around 35% opacity for bright backgrounds.

### Standard materials guidance
- Use standard blur/vibrancy/blending to structure content beneath functional chrome.
- Choose by semantic purpose, not perceived color.
- Favor vibrant foreground colors on materials to preserve legibility.
- Material thickness tradeoff:
- thicker = stronger contrast/readability
- thinner = more environmental continuity/context

### Platform considerations

### iOS, iPadOS
- Standard material tiers called out: ultra-thin, thin, regular (default), thick.
- Vibrancy guidance for labels/fills/separators across material types.
- Label vibrancy levels include default/secondary/tertiary/quaternary (with caveat against quaternary on very thin materials).

### macOS
- Use AppKit material roles intentionally.
- Validate where vibrancy helps communication in real contexts.
- Choose blending mode (`behindWindow` vs `withinWindow`) to match intended visual integration.

### tvOS
- Liquid Glass appears in system surfaces and focused states.
- Standard material recommendations are mapped by layer purpose and required brightness context.

### visionOS
- Windows default to adaptive system glass.
- No dedicated Dark Mode switch; material adapts to ambient luminance/content.
- Prefer translucency over opaque fills to preserve awareness of surroundings.
- Use thin/regular/thick standard materials for interactive emphasis, section separation, or dark contrast elements.
- Apply vibrancy hierarchy for text/symbol/fill legibility.

### watchOS
- Material layers help orientation and context in common full-screen modal flows.
- Avoid stripping default modal material backgrounds.

### Resources listed on page
- Related: Color, Accessibility, Dark Mode
- Developer docs: Adopting Liquid Glass, `glassEffect`, `Material`, UIKit/AppKit visual effect docs
- Videos: WWDC25/219 and WWDC25/356

### Change log (as listed)
- 2025-09-09: Liquid Glass guidance update
- 2025-06-09: Liquid Glass guidance added
- 2024-08-06: platform-specific art updates
- 2023-12-05: material/vibrancy terminology clarifications
- 2023-06-21: visionOS guidance updates
- 2023-06-05: watchOS modal material guidance

---

## 2) HIG: Layout
Source: https://developer.apple.com/design/human-interface-guidelines/layout

### Core definition
- Layout should be consistent and adaptive across contexts and device classes.

### Discussion highlights
- Layout should make control-content relationships immediately understandable.
- Apple design resources are referenced for templates/guides.

### Best practices
- Group related information with spacing, shapes, separators, or materials.
- Give high-priority information enough room and immediate visibility.
- Extend content to screen/window edges where appropriate.
- Account for floating control/navigation layers over content.
- Use background extension mechanisms when content would otherwise stop short of window edges.

### Visual hierarchy guidance
- Keep controls clearly distinct from content.
- Place important information near reading-order priority positions.
- Respect language directionality.
- Use alignment to improve scanability and hierarchy comprehension.
- Use progressive disclosure for hidden/overflow content.
- Ensure sufficient spacing around controls and between control groups.

### Adaptability guidance
- Design for trait/context changes across size, orientation, locale, text size, displays, and windowing.
- Use SwiftUI or Auto Layout to adapt dynamically.
- Support Dynamic Type and localization expansion/contraction.
- Test smallest and largest supported layouts first, then intermediate sizes.
- Scale artwork rather than distorting aspect ratio when adapting to display differences.

### Guides and safe areas
- Layout guides define positioning/alignment regions.
- Safe areas protect content from bars, hardware cutouts/housings, and interactive system regions.
- Respect platform safe areas and system controls by default.

### Platform considerations

### iOS
- Prefer supporting portrait and landscape when feasible.
- Full-bleed game UIs should still respect hardware geometry and interactive zones.
- Avoid edge-to-edge full-width buttons unless harmonized with margins/curvature.
- Keep status bar visible unless immersion/value justifies hiding.

### iPadOS
- Design for broad resizable-window ranges.
- Delay compact-mode switches until full layout truly no longer fits.
- Validate common system tiling sizes (halves/thirds/quadrants).
- Consider adaptable tab bar/sidebar navigation behavior.

### macOS
- Avoid putting critical UI at bottom edges that may be offscreen.
- Avoid placing content where camera housing could interfere.

### tvOS
- Layout does not auto-reflow per TV size the same way as touch platforms.
- Respect safe area margins (top/bottom 60 pt, sides 80 pt).
- Add enough padding for focus expansion states.
- Grid guidance supplied for 2–9 column variants.
- Keep spacing consistent and partial offscreen reveals symmetrical.

### visionOS
- Keep content within window bounds, especially near system control regions.
- Use ornaments for additional app controls outside content bounds.
- Keep interactive targets comfortably spaced (example guidance: center spacing around 60 pt).
- Mind z-depth clipping in standard windows.

### watchOS
- Favor edge-to-edge content use for limited screen area.
- Avoid too many side-by-side controls.
- Support autorotation where social/show-to-others use cases benefit.

### Specifications section highlights

### iOS/iPadOS dimensions table
- Page includes a detailed model-by-model dimensions matrix in points/pixels/scale.
- Coverage includes modern iPads and iPhones through iPhone 17 family plus legacy iPhone and iPod touch references.

### iOS/iPadOS size class table
- Page maps full-screen portrait/landscape width/height class combinations by model.
- iPads are regular/regular in both orientations in the listed full-screen scenarios.
- iPhones vary between compact-regular portrait and compact-compact or regular-compact landscape depending on model.

### watchOS dimensions table
- Page includes Apple Watch families and pixel dimensions by case size.

### Resources listed on page
- Related: Right to left, Spatial layout, Layout and organization
- Developer docs: composing custom layouts with SwiftUI
- Videos: WWDC25/356, WWDC22/10056, WWDC17/802

### Change log (as listed)
- 2025-09-09: added iPhone 17 / iPhone Air / Watch updates
- 2025-06-09: Liquid Glass guidance added
- 2025-03-07: new iPad/iPhone 16e specs update
- 2024-09-09: iPhone 16 + Watch 10 specs update
- 2024-06-10: organizational corrections
- 2024-02-02: iPadOS layout/control guidance + new iPad specs
- 2023-12-05: visionOS centering clarification
- 2023-09-15: iPhone 15 + Watch updates
- 2023-06-21: visionOS guidance inclusion
- 2022-09-14: iPhone 14 + Watch Ultra updates

---

## 3) HIG: Color
Source: https://developer.apple.com/design/human-interface-guidelines/color

### Core definition
- Color should be used intentionally for communication, hierarchy, feedback, and brand expression.

### Discussion highlights
- System colors adapt to background, appearance mode, vibrancy, and accessibility settings.
- Custom colors are supported but require careful variant planning.

### Best practices
- Do not reuse one color for conflicting meanings.
- Ensure compatibility across:
- light mode
- dark mode
- increased contrast
- Test in varied ambient lighting and across hardware display types/profiles.
- Consider translucency/artwork interactions that shift perceived color.
- Prefer system color pickers when users choose colors.

### Inclusive color
- Never rely on color alone for critical meaning.
- Provide non-color affordances (labels, symbols, shape/state cues).
- Maintain contrast and account for color-vision differences.
- Be aware of cross-cultural color interpretations.

### System colors guidance
- Avoid hard-coding system color values.
- Use semantic/dynamic system colors by intended role.
- Do not repurpose semantic colors for unrelated roles.

### Liquid Glass color guidance
- Glass is naturally colorless and influenced by underlying content.
- Tinting can emphasize priority controls (for example primary actions).
- Small elements can auto-flip light/dark behavior for contrast.
- Larger surfaces tend toward opacity adjustments for readability.
- Apply color sparingly to glass backgrounds and labels.
- Prefer background tint for primary action emphasis over widespread label coloring.
- Avoid color collisions between content-layer colors and control-layer colors in resting/default states.

### Color management
- Defines color space/profile concepts.
- Recommends embedding profiles in images.
- Recommends wide color (Display P3) where appropriate and supported.
- Suggests using asset-catalog variants for P3 vs sRGB when fidelity differences matter.

### Platform considerations

### iOS, iPadOS
- Distinguishes grouped vs ungrouped dynamic background families.
- Recommends primary/secondary/tertiary background layering semantics.
- Foreground semantic roles listed include label tiers, placeholders, separators, and links.

### macOS
- Page lists extensive AppKit dynamic color roles (selection, labels, separators, controls, window colors, etc.).
- App accent color behavior documented (multicolor vs user override behavior).
- Fixed-color sidebar icon exception noted for semantically meaningful icons.

### tvOS
- Recommends limited palette coordinated with brand/content.
- Focus indication should rely primarily on motion/scale responses rather than color alone.

### visionOS
- Recommends conservative color use on/with glass due environmental color influence.
- Prefer color in bold text/large areas for legibility.
- Keep brightness contrast balanced in immersive contexts to avoid discomfort.

### watchOS
- Background color should communicate context/information, not pure decoration.
- Notes tinted-mode behavior possibility for graphic complications.

### Specifications section highlights

### System colors table
- Includes unified colors (red, orange, yellow, green, mint, teal, cyan, blue, indigo, purple, pink, brown).
- For each, page provides default light, default dark, increased-contrast light, increased-contrast dark values.
- visionOS note: system colors use default dark values.

### iOS/iPadOS gray table
- Includes `systemGray` through `systemGray6` mappings with default and increased-contrast values.
- Notes SwiftUI equivalent mapping for `systemGray` to `Color.gray`.

### Resources listed on page
- Related: Dark Mode, Accessibility, Materials, Apple Design Resources
- Developer docs: SwiftUI `Color`, UIKit `UIColor`, AppKit color docs
- Videos: WWDC25/219

### Change log (as listed)
- 2025-12-16: Liquid Glass guidance update
- 2025-06-09: system values + Liquid Glass updates
- 2024-02-02: UIKit/SwiftUI gray distinctions + visionOS brightness note
- 2023-09-12: watchOS/tvOS color guidance updates
- 2023-06-21: visionOS inclusion
- 2023-06-05: watchOS color guidance update
- 2022-12-19: mint value correction in dark mode

---

## 4) SwiftUI: Applying Liquid Glass to custom views
Source: https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views

### Purpose
- Practical guide for custom Liquid Glass usage in SwiftUI.

### Main implementation topics
- Applying and configuring glass effects with `glassEffect(_:in:)`.
- Shape selection and tinting for emphasis.
- Interaction enhancement via glass interactivity APIs.
- Multi-element rendering with `GlassEffectContainer`.
- Controlled blending and morphing using container spacing.
- Geometry unification at rest via `glassEffectUnion(id:namespace:)`.
- Transition choreography using `glassEffectID(_:in:)` and `GlassEffectTransition` (`matchedGeometry`/`materialize`).
- Performance guidance: limit excessive containers/effects and profile rendering.

### Key behavior notes
- Modifier order matters: apply `glassEffect` after appearance-affecting modifiers so intended content is captured.
- Container spacing relative to internal stack spacing determines when glass blobs remain separate vs merge at rest.

---

## 5) SwiftUI Symbol: `glassEffect(_:in:)`
Source: https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:)

### Signature
```swift
nonisolated func glassEffect(_ glass: Glass = .regular, in shape: some Shape = DefaultGlassEffectShape()) -> some View
```

### Availability (as listed)
- iOS 26+
- iPadOS 26+
- macCatalyst 26+
- macOS 26+
- tvOS 26+
- watchOS 26+
- visionOS not listed for this symbol page

### Behavior
- Draws glass material behind the view shape.
- Applies foreground glass effects over content.
- Default variant is regular with a default capsule-like shape.
- Glass anchors to the target view’s bounds, including padding if padding is part of that view frame.
- Typical usage combines with `GlassEffectContainer` for coordinated multi-view behavior.

---

## 6) SwiftUI Symbol: `GlassEffectContainer`
Source: https://developer.apple.com/documentation/swiftui/glasseffectcontainer

### Type
```swift
@MainActor @preconcurrency struct GlassEffectContainer<Content> where Content : View
```

### Availability (as listed)
- iOS 26+
- iPadOS 26+
- macCatalyst 26+
- macOS 26+
- tvOS 26+
- watchOS 26+
- visionOS not listed for this symbol page

### Behavior
- Aggregates glass-contributing shapes from child views.
- Improves rendering efficiency versus isolated effects.
- Enables path blending and morphing among nearby elements.
- Spacing controls when path blending begins as elements approach.

---

## 7) SwiftUI Sample: Landmarks with Liquid Glass
Source: https://developer.apple.com/documentation/SwiftUI/Landmarks-Building-an-app-with-Liquid-Glass

### Purpose
- End-to-end sample of Liquid Glass adoption in a real SwiftUI app.

### Main concepts demonstrated
- `NavigationSplitView` foundation across iPhone/iPad/Mac.
- Background extension effect for edge-to-edge immersion under sidebars/inspectors.
- Horizontal scrolling content extending beneath side/inspector chrome.
- System toolbar glass and improved grouping strategy.
- Custom Liquid Glass badges and coordinated morph animations.
- App icon creation with Icon Composer layered icon approach.

### Section breakdown

### Apply a background extension effect
- Extends and blurs imagery under sidebar/inspector.
- Uses `backgroundExtensionEffect()`.
- Notes optional enhancements like safe-area overextension and pull-down expansion behavior.

### Extend horizontal scrolling under the sidebar
- Scroll rows are edge-aligned so cards can pass beneath sidebar/inspector regions.

### Refine the Liquid Glass in the toolbar
- Toolbar actions include sharing/favorites/collections/inspector toggles.
- System provides glass styling automatically.
- Grouping related actions improves clarity and utility.

### Display badges with Liquid Glass
- Custom badge view uses symbol + custom shape/color with `glassEffect`.
- Badge/toggle set wrapped in `GlassEffectContainer`.
- Stable effect identity via `glassEffectID(_:in:)` supports morph choreography.

### Create app icon with Icon Composer
- Multi-layer icon setup supports dynamic highlight/reflection behavior.
- Supports light/dark/clear/tinted icon variants.

### Topic links on sample page
- Applying a background extension effect
- Extending horizontal scrolling under sidebar/inspector
- Refining system-provided glass in toolbars
- Displaying custom activity badges

---

## Cross-page synthesis (practical implementation checklist)
- Keep Liquid Glass mostly in functional/navigation layers.
- Use standard materials for content-plane structuring.
- Apply tint sparingly; reserve for true emphasis.
- Validate all color decisions in light/dark/high-contrast contexts.
- Use semantic dynamic colors instead of hard-coded values.
- Make layout resilient to window resizing, orientation shifts, and localization expansion.
- Respect safe areas and system control zones (especially on iPad, macOS camera housing, visionOS windows, tvOS focus-safe margins).
- For custom glass controls:
- choose shape intentionally
- apply `glassEffect` after sizing/styling modifiers
- group related effects in `GlassEffectContainer`
- tune container spacing for intentional merge/morph behavior
- use stable IDs for transitions
- profile and cap effect count for performance

