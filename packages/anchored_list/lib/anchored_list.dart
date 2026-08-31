/// Scroll to any index in a lazy list, instantly and without glitches.
///
/// ```dart
/// AnchoredList.builder(
///   controller: controller,
///   itemCount: 100000,
///   itemBuilder: (context, index) => ListTile(title: Text('Item $index')),
/// )
///
/// controller.jumpToIndex(84213);
/// ```
library;

export 'src/anchored_list.dart' show AnchoredList;
export 'src/anchored_list_controller.dart'
    show AnchoredListBinding, AnchoredListController;
export 'src/item_position.dart' show ItemPosition;
