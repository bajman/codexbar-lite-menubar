# Widget Design Notes (CodexBar Lite)

This fork’s widget updates were aligned to Apple WidgetKit documentation and HIG guidance.

## Apple References

- [Creating a Widget Extension](https://developer.apple.com/documentation/widgetkit/creating-a-widget-extension)
- [Displaying the Right Widget Background](https://developer.apple.com/documentation/widgetkit/displaying-the-right-widget-background)
- [Preparing Widgets for Additional Platforms, Contexts, and Appearances](https://developer.apple.com/documentation/widgetkit/preparing-widgets-for-additional-platforms-contexts-and-appearances)
- [SwiftUI `widgetContentMargins` environment](https://developer.apple.com/documentation/swiftui/environmentvalues/widgetcontentmargins)
- [SwiftUI `showsWidgetContainerBackground` environment](https://developer.apple.com/documentation/swiftui/environmentvalues/showswidgetcontainerbackground)
- [Human Interface Guidelines: Widgets](https://developer.apple.com/design/human-interface-guidelines/widgets)

## Implemented Decisions

- Use `contentMarginsDisabled()` on widget configurations and apply explicit `widgetContentMargins` in a shared surface view.
- Respect `showsWidgetContainerBackground` and provide a context-appropriate widget background.
- Respect `widgetRenderingMode` to keep backgrounds and accents readable in tinted/accented contexts.
- Keep hierarchy glanceable:
  - provider + relative freshness timestamp
  - session/weekly bars first
  - secondary metrics after primary bars
- Add a CodexBar-style two-tier meter glyph in headers to visually match the menu bar meter language.
