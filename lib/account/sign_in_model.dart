import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter_scene/scene.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../app_theme.dart';

/// The 3D model on the sign-in screen (`assets/scene/keyboard-three-js.glb`),
/// turning slowly. Drawn with flutter_scene (Flutter GPU, on by
/// `FLTEnableFlutterGPU` in the Mac app's Info.plist) on a transparent
/// background, so the screen shows behind it.
///
/// Lit to match the theme: the ambient light is the background color picked
/// in Settings, and two lights in the accent color shine on it: one from
/// above and in front, and one from the camera toward the model. Then
/// a light map (`shaders/light_map.frag`) recolors the drawn scene from
/// the background color: shadows a darker shade of it, highlights a
/// lighter tint mixed with the accent.
/// Nothing shows until the model has loaded, and nothing at all if it
/// can't be drawn (an error is logged): the screen works without it.
class SignInModel extends StatefulWidget {
  /// Fills the space it's given (the whole window, on the sign-in
  /// screen).
  const SignInModel({super.key});

  static const asset = 'assets/scene/keyboard-three-js.glb';

  /// One turn every this-many seconds.
  static const turnSeconds = 24.0;

  /// How long the scene takes to fade in, once it's ready.
  static const fadeDuration = Duration(milliseconds: 1200);

  @override
  State<SignInModel> createState() => _SignInModelState();
}

class _SignInModelState extends State<SignInModel>
    with SingleTickerProviderStateMixin {
  final _scene = Scene();

  /// The loaded model, under a pivot that turns it about its own center.
  bool _loaded = false;
  bool _failed = false;

  /// The background and accent colors the lights were last set from.
  (Color, Color)? _litFor;

  /// The fill light from the camera, in the accent color (updated with it).
  final _cameraLight = DirectionalLight(
    color: vm.Vector3(1, 1, 1),
    intensity: 1.0,
  );

  /// The light map, once compiled (null until then, or where shader
  /// filters aren't supported: the scene then shows as lit).
  ui.FragmentShader? _lightMap;

  /// The light map has compiled, or won't (unsupported, or failed): the
  /// scene waits for it, so its colors don't change once it shows.
  bool _lightMapDone = false;

  /// The fade in, started on the first frame the scene actually draws
  /// (after its shaders have compiled: see [SceneView.warmUp]), so a slow
  /// start doesn't eat it and it never snaps in.
  late final _fade = AnimationController(
    vsync: this,
    duration: SignInModel.fadeDuration,
  );
  // Starts slowly, so it eases out of nothing rather than popping in.
  late final _opacity = CurvedAnimation(parent: _fade, curve: Curves.easeInOut);

  @override
  void initState() {
    super.initState();
    _load();
    _loadLightMap();
  }

  Future<void> _loadLightMap() async {
    ui.FragmentShader? shader;
    if (ui.ImageFilter.isShaderFilterSupported) {
      try {
        shader = (await _lightMapProgram).fragmentShader();
      } catch (e, stack) {
        FlutterError.reportError(
          FlutterErrorDetails(exception: e, stack: stack, library: 'light map'),
        );
      }
    }
    if (!mounted) {
      shader?.dispose();
      return;
    }
    setState(() {
      _lightMap = shader;
      _lightMapDone = true;
    });
  }

  /// Each frame the scene draws (none before its shaders have compiled):
  /// moves the fade on.
  void _onTick(Duration elapsed, double deltaSeconds) {
    if (_fade.isCompleted) return;
    // At most a 60fps frame's worth per frame, so the slow first frames
    // after it appears can't jump the fade ahead (see FadeInView).
    final step = math.min(deltaSeconds, 1 / 60);
    _fade.value =
        _fade.value + step * 1e6 / SignInModel.fadeDuration.inMicroseconds;
  }

  Future<void> _load() async {
    try {
      await Scene.initializeStaticResources();
      final model = await Node.fromGlbAsset(SignInModel.asset);
      // Signed in while it loaded: the scene is gone; nothing to add to.
      if (!mounted) return;
      // Centered on the pivot and scaled to about one unit across, so it
      // turns in place whatever the file's own origin and size.
      final fit = Node()..add(model);
      if (model.combinedLocalBounds case final box?) {
        final center = (box.min + box.max) * 0.5;
        final extent = box.max - box.min;
        final largest = math.max(extent.x, math.max(extent.y, extent.z));
        final s = largest > 0 ? 1.0 / largest : 1.0;
        fit.localTransform = vm.Matrix4.diagonal3Values(s, s, s)
          ..translateByVector3(-center);
      }
      final pivot = Node()
        ..add(fit)
        // Tipped toward the camera a little, so its top shows.
        ..rotation = vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), 0.35)
        ..addComponent(_Spin(2 * math.pi / SignInModel.turnSeconds));
      _scene
        ..add(pivot)
        // A dim fill light from the camera: it travels the way the camera
        // looks, so the faces turned toward the viewer never go dark.
        ..add(
          Node(name: 'camera light')..addComponent(
            DirectionalLightComponent.aimed(
              _cameraLight,
              vm.Vector3.zero() - _cameraPosition,
            ),
          ),
        );
      if (mounted) setState(() => _loaded = true);
    } catch (e, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: e,
          stack: stack,
          library: 'sign-in model',
        ),
      );
      if (mounted) setState(() => _failed = true);
    }
  }

  /// Ambient light in the background color; the light from above and in
  /// front, and the one from the camera, in the accent color (Settings).
  void _light(Color background, Color accent) {
    if (_litFor == (background, accent)) return;
    _litFor = (background, accent);
    double linear(double c) => math.pow(c, 2.2).toDouble();
    // Lights take linear RGB.
    final accentLight = vm.Vector3(
      linear(accent.r),
      linear(accent.g),
      linear(accent.b),
    );
    _cameraLight.color = accentLight;
    const ambient = 0.9;
    _scene
      ..environment = EnvironmentMap.constantDiffuse(
        vm.Vector3(
          linear(background.r) * ambient,
          linear(background.g) * ambient,
          linear(background.b) * ambient,
        ),
      )
      ..directionalLight = DirectionalLight(
        // The way the light travels: down, and away from the camera.
        direction: vm.Vector3(-0.3, -1.0, 0.6),
        color: accentLight.clone(),
        intensity: 1.4,
      );
  }

  /// The light map's ramp from [background], with [accent] in its
  /// highlights, and the fade's [opacity].
  ui.ImageFilter _lightMapFilter(
    ui.FragmentShader shader,
    Color background,
    Color accent,
    double opacity,
  ) {
    var i = 2; // 0 and 1 are the size, set by the engine.
    void color(Color c) {
      shader
        ..setFloat(i++, c.r)
        ..setFloat(i++, c.g)
        ..setFloat(i++, c.b);
    }

    // Shadows a darker shade of the background; mid-tones a lighter tint
    // of it, well into the accent; highlights the accent itself, a touch
    // paler. Most of the model is mid-tone, so the accent shows across it.
    color(Color.lerp(background, Colors.black, 0.45)!);
    color(
      Color.lerp(Color.lerp(background, Colors.white, 0.22)!, accent, 0.45)!,
    );
    color(Color.lerp(accent, Colors.white, 0.15)!);
    shader
      ..setFloat(i++, 1) // Fully mapped.
      ..setFloat(i, opacity);
    return ui.ImageFilter.shader(shader);
  }

  /// Leaving the sign-in screen (signing in removes it) stops everything:
  /// the view's ticker goes with it, and the scene's GPU resources and the
  /// shader are freed here. Nothing renders while the app is in use.
  @override
  void dispose() {
    _opacity.dispose();
    _fade.dispose();
    _lightMap?.dispose();
    _scene.dispose();
    super.dispose();
  }

  /// [scene] through the light map, once it's ready.
  /// With the light map, the fade is done in the shader (an opacity
  /// widget around it doesn't reach the screen under Impeller); without
  /// one, by a plain FadeTransition.
  Widget _faded(BuildContext context, Widget scene) => switch (_lightMap) {
    final shader? => AnimatedBuilder(
      animation: _opacity,
      child: scene,
      builder: (context, scene) => ImageFiltered(
        imageFilter: _lightMapFilter(
          shader,
          context.colors.surface,
          Theme.of(context).colorScheme.primary,
          _opacity.value,
        ),
        child: scene,
      ),
    ),
    null => FadeTransition(
      // Never quite 0: a fully transparent child isn't painted, and the
      // view has to draw for its first frame (and the fade) to start.
      opacity: _opacity.drive(Tween(begin: 0.002, end: 1)),
      child: scene,
    ),
  };

  @override
  Widget build(BuildContext context) {
    if (_failed) return const SizedBox.expand();
    _light(context.colors.surface, Theme.of(context).colorScheme.primary);
    // Nothing until the model and the light map are both ready; then the
    // view compiles its shaders (warmUp) before its first frame, and that
    // frame starts the fade.
    if (!_loaded || !_lightMapDone) return const SizedBox.expand();
    return SizedBox.expand(
      child: _faded(
        context,
        SceneView(
          _scene,
          warmUp: true,
          onTick: _onTick,
          camera: PerspectiveCamera(
            position: _cameraPosition,
            target: vm.Vector3.zero(),
            // Rolled 25° about the way it looks.
            up: _cameraUp,
            // Zoomed in 2x: half the view's height at the model
            // (tan(fov / 2) halved from a 40° view).
            fovRadiansY: _zoomedFov,
          ),
        ),
      ),
    );
  }
}

/// Compiled once for the app's run.
final _lightMapProgram = ui.FragmentProgram.fromAsset('shaders/light_map.frag');

/// Where the camera is: a little above the model, in front of it.
final _cameraPosition = vm.Vector3(0, 0.35, -1.6);

/// The camera's up direction: straight up, rolled 25° about the line from
/// the camera to the model, so the view is tilted.
final _cameraUp = vm.Quaternion.axisAngle(
  (vm.Vector3.zero() - _cameraPosition).normalized(),
  25 * vm.degrees2Radians,
).rotated(vm.Vector3(0, 1, 0));

/// The camera's vertical field of view: a 40° view zoomed in 2x.
final _zoomedFov = 2 * math.atan(math.tan(20 * vm.degrees2Radians) / 2);

/// Turns its node about the side-to-side (X) axis at [radiansPerSecond]:
/// it tumbles end over end toward the camera.
class _Spin extends Component {
  _Spin(this.radiansPerSecond);
  final double radiansPerSecond;

  @override
  void update(double deltaSeconds) {
    node.rotation =
        vm.Quaternion.axisAngle(
          vm.Vector3(1, 0, 0),
          radiansPerSecond * deltaSeconds,
        ) *
        node.rotation;
  }
}
