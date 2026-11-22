{{flutter_js}}
{{flutter_build_config}}

const luxuryConfig = window.luxuryFlutterConfig ?? {};
_flutter.loader.load({
  config: luxuryConfig,
  onEntrypointLoaded: async (initializer) => {
    try {
      const app = await initializer.initializeEngine(luxuryConfig);
      await app.runApp();
    } catch (error) {
      console.error(error);
      window.showLuxuryStartupError();
    }
  },
}).catch((error) => {
  console.error(error);
  window.showLuxuryStartupError();
});
