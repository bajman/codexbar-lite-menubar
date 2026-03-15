# Apple Liquid Glass + HIG + SwiftUI + WWDC25 Consolidated Notes

## Capture Metadata
- Capture scope: the exact URLs provided in the request.
- Capture date (UTC): 2026-02-28 23:16:17Z.
- Method: direct fetch of Apple documentation markdown endpoints and WWDC session HTML sections (About, Summary, Transcript metadata, Chapters, Resources, Code snippets).
- Output goal: exhaustive, structured, implementation-focused consolidation in one file.

## Source Index (Exact URLs)
- https://developer.apple.com/documentation/TechnologyOverviews/liquid-glass
- https://developer.apple.com/design/human-interface-guidelines/
- https://developer.apple.com/documentation/SwiftUI/Applying-Liquid-Glass-to-custom-views
- https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:)
- https://developer.apple.com/documentation/swiftui/glasseffectcontainer
- https://developer.apple.com/videos/play/wwdc2025/219/
- https://developer.apple.com/videos/play/wwdc2025/323/
- https://developer.apple.com/videos/play/wwdc2025/256/
- https://developer.apple.com/documentation/SwiftUI/Landmarks-Building-an-app-with-Liquid-Glass

---

## 1) Apple Overview: Liquid Glass + HIG

## 1.1 Liquid Glass Technology Overview
Source: https://developer.apple.com/documentation/TechnologyOverviews/liquid-glass

### Page purpose
- Introduces Liquid Glass as Apple’s cross-platform dynamic material language.
- Frames adoption around design consistency and platform-native behavior.

### Core framing
- Liquid Glass is presented as a dynamic visual material with glass-like optics and fluid behavior.
- Standard controls/navigation in SwiftUI/UIKit/AppKit pick this up automatically.
- Custom interfaces can also opt in using dedicated APIs.

### Adopting Liquid Glass (high-level guidance)
- Rebuild with latest Xcode SDKs first to see automatic visual/system updates.
- Keep existing app structure where possible; adoption is iterative, not a full rewrite.
- Align materials, controls, icons, and navigation/search behavior with system patterns.
- Validate windows/modals/menus/toolbars against updated platform conventions.
- Test across devices/platforms for consistency.

### Sample-code emphasis
- Highlights Landmarks as the canonical Liquid Glass sample.
- Focus areas called out by Apple:
- Icon Composer workflow for icon layers/variants.
- Edge-to-edge content and background extension effects.
- Horizontal scroll extension under sidebars/inspectors.
- Window-size adaptation.
- Cross-platform search conventions.
- Custom glass effects and transitions.

### Design-principle emphasis
- Refers directly to HIG for practical design constraints.
- Themes emphasized:
- Visual hierarchy.
- Hardware/software harmony (concentric geometry, fitting rounded device language).
- Platform consistency across windows and display sizes.
- Controlled use of color/tint for legibility and emphasis.

### Linked videos in this overview page
- WWDC25/219, WWDC25/356, WWDC25/323, WWDC25/284, WWDC25/310.

### Topic link
- Essentials: Adopting Liquid Glass.

---

## 1.2 Human Interface Guidelines (HIG) Landing
Source: https://developer.apple.com/design/human-interface-guidelines/

### Page purpose
- Entry point to Apple’s design system guidance across all platforms.

### Three stated principles
- Hierarchy: controls and chrome should elevate content without overpowering it.
- Harmony: interface geometry should align with platform/device shape language.
- Consistency: follow platform conventions so UI adapts predictably across contexts.

### Design fundamentals listed
- App icons.
- Color.
- Materials.
- Layout.
- Icons.
- Accessibility.

### “New and updated” items listed
- Multitasking.
- Menu bar.
- Toolbars.
- Search fields.
- Game Center.
- Generative AI.

### HIG topic navigation buckets listed
- Getting started.
- Foundations.
- Patterns.
- Components.
- Inputs.
- Technologies.

### Relationship to Liquid Glass
- HIG landing explicitly points developers to “Adopting Liquid Glass” for implementation guidance.

---

## 2) SwiftUI Glass APIs and Behaviors

## 2.1 Applying Liquid Glass to custom views
Source: https://developer.apple.com/documentation/SwiftUI/Applying-Liquid-Glass-to-custom-views

### Scope of the article
- Canonical practical guide for custom Liquid Glass in SwiftUI.
- Covers configuration, grouping/merging, morph transitions, and performance.

### Liquid Glass behavior model (as described)
- Background blur + adaptive optical response.
- Reflects surrounding light/color context.
- Reacts to touch/pointer in real time.
- Built-in controls already adopt it; custom views can opt in.

### API: `glassEffect(_:in:)`
- Primary modifier to apply glass to a custom view.
- Default behavior:
- Uses `Glass.regular`.
- Uses default capsule-like shape unless overridden.

### Customization knobs
- Shape override (for visual coherence, e.g., rounded rects).
- Tinting for emphasis.
- Interaction behaviors via `.interactive()` for touch/pointer response.

### Critical modifier-order note
- `glassEffect(_:in:)` captures rendered content sent to the container.
- Therefore apply it after modifiers that affect appearance/layout you want captured (for example padding, frame, font, etc.).

### Working with multiple glass views: `GlassEffectContainer`
- Group related glass views inside `GlassEffectContainer` for:
- Better rendering performance.
- Blending between nearby glass paths.
- Morphing behavior during transitions.

### Spacing mechanics (important for layout/padding interaction)
- Container spacing controls when nearby glass paths start blending.
- Larger container spacing means blending can begin earlier as views approach.
- If container spacing exceeds interior layout spacing, glass may merge even at rest.
- Animating position/visibility then drives split/merge morph behavior.

### Unioning multiple geometries at rest
- `glassEffectUnion(id:namespace:)` can combine multiple views into one shared glass envelope.
- Useful when views are dynamic or not tightly co-located in one stack arrangement.

### Transition/morph APIs
- `glassEffectID(_:in:)` assigns stable identity for effect morphing across hierarchy changes.
- `GlassEffectTransition` controls transition style.
- `matchedGeometry` is the default for in-range effects.
- `materialize` is recommended for farther-apart add/remove transitions or custom choreography.

### Performance guidance in article
- Avoid too many independent containers.
- Avoid too many off-container effects.
- Limit concurrent on-screen glass complexity.
- Profile animation/render performance with Apple’s recommended tools/videos.

---

## 2.2 `glassEffect(_:in:)` symbol page
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
- visionOS: not listed for this symbol page

### Behavior notes
- Renders a glass shape behind the view.
- Applies foreground glass treatment over the view content.
- Anchors to the view bounds at time of application.
- Practical implication: if padding is applied before `glassEffect`, the padded frame is part of the glass footprint.

### Typical usage pattern
- Use with `GlassEffectContainer` when coordinating several glass views.

---

## 2.3 `GlassEffectContainer` symbol page
Source: https://developer.apple.com/documentation/swiftui/glasseffectcontainer

### Type
```swift
@MainActor @preconcurrency struct GlassEffectContainer<Content> where Content : View
```

### Purpose
- Aggregates multiple glass-contributing views into a coordinated set.
- Enables:
- Shared rendering pass characteristics.
- Performance improvements vs isolated effects.
- Shape interaction/morphing across members.

### Spacing model
- Container spacing defines proximity threshold for blend behavior.
- Higher spacing -> earlier blending onset during approach.

### Availability (as listed)
- iOS 26+
- iPadOS 26+
- macCatalyst 26+
- macOS 26+
- tvOS 26+
- watchOS 26+
- visionOS: not listed for this symbol page

---

## 3) Landmarks Sample (Comprehensive Reference)
Source: https://developer.apple.com/documentation/SwiftUI/Landmarks-Building-an-app-with-Liquid-Glass

### Purpose and platform scope
- SwiftUI sample demonstrating end-to-end Liquid Glass adoption patterns.
- Target platforms listed: iOS 26+, macOS 26+ (with Xcode 26+).
- App uses `NavigationSplitView` as foundational structure.

### Major implementation patterns highlighted
- Background extension for immersive edge-to-edge experiences.
- Horizontal scrolls extending under sidebar/inspector layers.
- System-provided toolbar glass and grouping refinement.
- Custom badge components with glass + transition IDs.
- Icon Composer workflow for layered app icons/variants.

### Feature-by-feature notes

### Background extension effect
- Applied to key images (hero/header/detail media).
- Image extends/blur-underlays sidebars/inspectors to avoid clipped feel.
- Uses `backgroundExtensionEffect()`.
- Notes mention optional safe-area overextension and pull-to-stretch style behavior as enhancement.

### Horizontal scrolling under sidebars/inspectors
- Scroll rows aligned to container edges so content can pass under floating structural chrome.
- Preserves immersive context while retaining navigation affordances.

### Toolbar refinement
- Toolbar actions include share/favorite/collections/inspector actions.
- System auto-applies glass to toolbar controls.
- Sample emphasizes grouping related actions instead of one undifferentiated cluster.

### Custom badges with Liquid Glass
- Badge view uses symbol + custom background geometry/color.
- Applies `glassEffect(_:in:)`.
- Wraps badges and controls in `GlassEffectContainer`.
- Uses `glassEffectID(_:in:)` per badge for coordinated morph animations.

### Icon Composer
- App icon built with layered structure compatible with dynamic lighting/specular behavior.
- Supports appearance variants (light/dark/clear/tinted) exposed by system personalization.

### Related Landmarks topic pages listed on sample page
- Applying a background extension effect.
- Extending horizontal scrolling under a sidebar or inspector.
- Refining system-provided glass effect in toolbars.
- Displaying custom activity badges.

---

## 4) WWDC25 Session Consolidation

## 4.1 WWDC25 Session 219: Meet Liquid Glass
Source: https://developer.apple.com/videos/play/wwdc2025/219/
Published: 2025-06-09

### About (page intent)
- Design-first explanation of Liquid Glass philosophy.
- Focuses on optical model, dynamic behavior, adaptation rules, and usage principles.

### Chapter map
- 0:00 Introduction
- 1:29 Dynamics
- 6:00 Adaptivity
- 10:31 Principles
- 18:53 Next steps

### Chapter summaries (consolidated)

### Introduction
- Defines Liquid Glass as a digital material layer for cross-platform UI.
- Positions it as both visual and behavioral evolution, not just a static style update.

### Dynamics
- Emphasizes lensing/light-shaping behavior for separation and depth.
- Highlights interaction response: flexing, energizing, and fluid transitions.
- Motivates shape continuity and morphing between controls/states.

### Adaptivity
- Material adapts continuously to background content and scale.
- Large surfaces shift depth cues (shadow, refraction, light response) vs small controls.
- Scroll-edge behavior supports legibility by lifting control layers from moving content.

### Principles
- Use glass primarily in navigation/chrome layer, not deep content layer.
- Avoid stacking glass-on-glass excessively.
- Distinguishes Regular vs Clear variants and when Clear is appropriate.
- Reinforces selective tint usage for emphasis only.
- Notes automatic accessibility responses (reduced transparency/contrast/motion contexts).

### Next steps
- Frames Liquid Glass as unifying visual language across Apple platforms.
- Calls for practical adoption in real app flows.

### Session resources listed
- Adopting Liquid Glass: https://developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass
- HIG: https://developer.apple.com/design/human-interface-guidelines
- HIG Materials: https://developer.apple.com/design/human-interface-guidelines/materials
- HD video download: https://devstreaming-cdn.apple.com/videos/wwdc/2025/219/4/476dabc8-f3bb-4190-8929-4ba7131c939d/downloads/wwdc2025-219_hd.mp4?dl=1
- SD video download: https://devstreaming-cdn.apple.com/videos/wwdc/2025/219/4/476dabc8-f3bb-4190-8929-4ba7131c939d/downloads/wwdc2025-219_sd.mp4?dl=1

---

## 4.2 WWDC25 Session 323: Build a SwiftUI app with the new design
Source: https://developer.apple.com/videos/play/wwdc2025/323/
Published: 2025-06-09

### About (page intent)
- Practical implementation session for integrating Liquid Glass into a SwiftUI app.
- Centers on structure/toolbars/search/controls/custom-glass techniques.

### Chapter map
- 0:00 Introduction
- 3:07 App structure
- 7:49 Toolbars
- 11:10 Search
- 14:03 Controls
- 17:57 Liquid Glass effects
- 21:31 Next steps

### Chapter summaries (consolidated)

### Introduction
- Rebuild with new SDKs to get broad baseline updates automatically.
- Uses Landmarks as migration/adoption walkthrough.

### App structure
- Updated `NavigationSplitView`, `TabView`, and sheet behaviors for new design.
- Sidebars float with glass styling.
- `backgroundExtensionEffect` enables non-clipped immersive imagery behind structural chrome.
- Tab bars can minimize to prioritize content.
- Presentations (sheets/menus/popovers/dialogs) can morph from source controls for continuity.

### Toolbars
- Toolbars float on adaptive glass.
- Automatic grouping exists; `ToolbarSpacer` can refine grouping density and readability.
- Monochrome icon handling and scroll-edge legibility behavior are emphasized.

### Search
- Two patterns: toolbar search and dedicated search destination/tab.
- Placement adapts by platform form factor and role.

### Controls
- Cross-platform visual family update (shape/size/spacing consistency).
- Button and slider refinements, including ticks/fill behavior.
- Emphasis on corner concentricity and alignment correctness.

### Liquid Glass effects
- Custom UI can use `glassEffect` + shape/tint/interaction.
- Grouping with `GlassEffectContainer` recommended for coherent visuals.
- `glassEffectID` supports fluid morphing transitions.

### Next steps
- Audit old background/fill assumptions.
- Remove unnecessary custom chrome where system glass now provides intended layering.

### Session resources listed
- Applying Liquid Glass to custom views: https://developer.apple.com/documentation/SwiftUI/Applying-Liquid-Glass-to-custom-views
- Landmarks sample: https://developer.apple.com/documentation/SwiftUI/Landmarks-Building-an-app-with-Liquid-Glass
- Adopting Liquid Glass: https://developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass
- HD video download: https://devstreaming-cdn.apple.com/videos/wwdc/2025/323/4/0fd37581-632a-4827-b656-d192163cece0/downloads/wwdc2025-323_hd.mp4?dl=1
- SD video download: https://devstreaming-cdn.apple.com/videos/wwdc/2025/323/4/0fd37581-632a-4827-b656-d192163cece0/downloads/wwdc2025-323_sd.mp4?dl=1

---

## 4.3 WWDC25 Session 256: What’s new in SwiftUI
Source: https://developer.apple.com/videos/play/wwdc2025/256/
Published: 2025-06-09

### About (page intent)
- Broader SwiftUI release session with a dedicated Liquid Glass/new design segment.
- Also covers performance tooling, layout foundations, platform expansion, web/rich text.

### Chapter map
- 0:00 Introduction
- 1:22 Make the new design shine
- 6:59 Framework foundations
- 14:33 SwiftUI across the system
- 20:04 Expand SwiftUI views
- 25:01 Next steps

### Chapter summaries (consolidated)

### Introduction
- Frames session as full-stack SwiftUI update: visuals, performance, layout, new surfaces.

### Make the new design shine
- Covers navigation/toolbar/search/control changes associated with Liquid Glass era.
- Emphasizes automatic gains from recompiling plus optional customization APIs.
- Calls out iPad menu bar behavior and resizing considerations.

### Framework foundations
- Performance, animation, and layout foundations updated.
- Mentions new profiling instrument and animation/layout-focused API improvements.

### SwiftUI across the system
- Expands scene/surface interoperability across Apple platform stacks.
- Mentions Scene bridging and additional scene types.

### Expand SwiftUI views
- Adds web content and richer content interaction surface area.
- Mentions 3D charts, improved drag/drop, rich-text editor pathways.

### Next steps
- Encourages developers to mix automatic adoption with targeted API upgrades.

### Code snippet index surfaced on this session page
- 2:27 Toolbar spacer
- 2:52 Toolbar item tint
- 3:30 Searchable
- 4:12 Search tab
- 4:37 Glass effect
- 5:20 Menu bar commands
- 6:40 Window resize anchor
- 11:24 `@Animatable` macro
- 12:15 Spatial overlay
- 13:04 Manipulable + surface snapping
- 15:00 SwiftUI scenes
- 16:28 Assistive Access scene
- 17:52 SwiftUI presentations from RealityKit
- 19:24 Level of detail
- 20:28 WebView
- 20:44 WebView with `WebPage`
- 21:35 3D charts
- 22:18 macOS drag and drop
- 23:55 Rich text view

### Session resources listed
- Applying Liquid Glass to custom views: https://developer.apple.com/documentation/SwiftUI/Applying-Liquid-Glass-to-custom-views
- Populating SwiftUI menus with adaptive controls: https://developer.apple.com/documentation/SwiftUI/Populating-SwiftUI-menus-with-adaptive-controls
- Adopting Liquid Glass: https://developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass
- HIG: https://developer.apple.com/design/human-interface-guidelines
- HD video download: https://devstreaming-cdn.apple.com/videos/wwdc/2025/256/4/353ed635-9639-48db-8c8c-69b2b7e499c1/downloads/wwdc2025-256_hd.mp4?dl=1
- SD video download: https://devstreaming-cdn.apple.com/videos/wwdc/2025/256/4/353ed635-9639-48db-8c8c-69b2b7e499c1/downloads/wwdc2025-256_sd.mp4?dl=1

---

## 5) Cross-Source Implementation Synthesis (Design + SwiftUI)

### 5.1 Layout, padding, and glass footprints
- Glass anchoring follows the view bounds at modifier application.
- Practical rule: apply padding/frame/shape-affecting modifiers before `glassEffect` when those dimensions should define the capsule/path.
- For custom elements, choose shape intentionally to match control scale and surrounding geometry.

### 5.2 Container spacing and merge behavior
- `GlassEffectContainer(spacing:)` is a visual interaction threshold.
- Keep container spacing coherent with stack spacing to avoid accidental always-merged blobs.
- Use animation + identity APIs (`glassEffectID`) to make merges/splits look purposeful.

### 5.3 Hierarchy discipline
- Keep glass in structure/navigation layers unless a clear UX reason exists.
- Avoid deep layering of multiple glass planes.
- Prefer content richness in background/content layers over excessive tinted foreground controls.

### 5.4 Tinting discipline
- Tint is emphasis, not default fill replacement.
- Over-tinting collapses hierarchy and weakens affordance clarity.

### 5.5 Motion + transition consistency
- Prefer Apple-provided morph/materialize pathways over ad-hoc opacity-only transitions.
- Maintain stable IDs for views participating in hierarchy changes.

### 5.6 Accessibility and adaptability
- Expect system accessibility settings to modify material treatment automatically.
- Test with Reduced Transparency, Increased Contrast, and Reduced Motion enabled.

### 5.7 Migration strategy (practical)
- Rebuild first, observe automatic upgrades.
- Remove obsolete custom backgrounds/chrome that conflict with new system layers.
- Then add custom glass selectively where product differentiation matters.

---

## 6) Quick API Inventory Mentioned Across Sources
- `glassEffect(_:in:)`
- `GlassEffectContainer`
- `glassEffectUnion(id:namespace:)`
- `glassEffectID(_:in:)`
- `GlassEffectTransition` (`matchedGeometry`, `materialize`)
- `backgroundExtensionEffect()`
- `ToolbarSpacer`
- `tabBarMinimizeBehavior`
- `tabViewBottomAccessory`
- `searchable` + search-role tab behavior
- `commands` (menu bar reuse on iPad/macOS contexts)
- Window resize anchor APIs

---

## 7) Appendix: Canonical Documentation Endpoints Resolved During Capture
- https://docs.developer.apple.com/tutorials/data/documentation/TechnologyOverviews/liquid-glass.md
- https://docs.developer.apple.com/tutorials/data/design/human-interface-guidelines.md
- https://docs.developer.apple.com/tutorials/data/documentation/SwiftUI/Applying-Liquid-Glass-to-custom-views.md
- https://docs.developer.apple.com/tutorials/data/documentation/swiftui/view/glasseffect(_:in:).md
- https://docs.developer.apple.com/tutorials/data/documentation/swiftui/glasseffectcontainer.md
- https://docs.developer.apple.com/tutorials/data/documentation/SwiftUI/Landmarks-Building-an-app-with-Liquid-Glass.md

