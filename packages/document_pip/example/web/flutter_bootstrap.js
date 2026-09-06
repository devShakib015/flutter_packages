{{flutter_js}}
{{flutter_build_config}}

// Multi-view has to be switched on here, and the app runner handed over,
// because only it can add a view — dart:ui_web exposes the views read-only.
_flutter.loader.load({
  config: { multiViewEnabled: true },
  onEntrypointLoaded: async function (engineInitializer) {
    const engine = await engineInitializer.initializeEngine({
      multiViewEnabled: true,
    });
    const app = await engine.runApp();
    window.documentPipApp = app;

    // In multi-view mode no view is created for you, so the page's own view is
    // added explicitly.
    app.addView({ hostElement: document.querySelector('#app') });
  },
});
