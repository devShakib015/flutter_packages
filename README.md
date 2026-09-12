# devShakib Flutter packages

[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.22255262.svg)](https://doi.org/10.5281/zenodo.22255262)

Open-source Flutter packages published to pub.dev. A Dart pub workspace — one
lockfile, one `.dart_tool`, members resolved by path.

Every tagged release is archived on Zenodo and gets its own DOI; the badge
above points at the concept DOI, which always resolves to the latest version.

| Package | Description | Platforms |
| --- | --- | --- |
| [loading_kit](packages/loading_kit) | A blocking-async overlay that never flickers | All |
| [apple_foundation_models](packages/apple_foundation_models) | Run Apple's on-device language model from Flutter | iOS, macOS |
| [fit_text](packages/fit_text) | Text that shrinks to fit, including inside `IntrinsicHeight` and `Table` | All |
| [vitals](packages/vitals) | Type-safe Apple Health and Health Connect | iOS, Android |
| [anchored_list](packages/anchored_list) | Jump to any index in a lazy list, in constant time | All |
| [masonry_kit](packages/masonry_kit) | Pinterest-style masonry grids, as a sliver or a box widget | All |
| [apple_intelligence](packages/apple_intelligence) | On-device image generation, Writing Tools and Genmoji | iOS, macOS |
| [roomplan](packages/roomplan) | Scan a room with Apple's RoomPlan and get it back as data | iOS |
| [file_system_access](packages/file_system_access) | Real files on Flutter Web: save in place, reopen after a reload | Web |
| [ar_quick_look](packages/ar_quick_look) | Show a 3D model in the room with Apple's own AR viewer | iOS |
| [cross_tab](packages/cross_tab) | Messages, presence and leader election across browser tabs | Web |
| [woo_client](packages/woo_client) | WooCommerce for Dart: the keyless Store API and the admin REST API | All |
| [document_pip](packages/document_pip) | Live Flutter widgets in an always-on-top window, from Flutter Web | Web |

The Apple packages also need the matching hardware: `roomplan` needs a LiDAR
sensor, and `apple_foundation_models` and `apple_intelligence` need a device
with Apple Intelligence.

```bash
flutter pub get
cd packages/loading_kit && flutter test
```

`apple_foundation_models` also carries integration tests that run against the
real on-device model. They need Apple Intelligence hardware on macOS 26:

```bash
cd packages/apple_foundation_models/example
flutter test integration_test/plugin_test.dart -d macos
```

MIT © K M Shahriar Hossain
