import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Utility class for defining and managing keyboard shortcuts
/// for power users across the application
class KeyboardShortcuts {
  /// Common shortcuts used throughout the app
  static const Map<String, String> shortcuts = {
    'Ctrl/Cmd + N': 'Create new item',
    'Ctrl/Cmd + S': 'Save changes',
    'Ctrl/Cmd + F': 'Search',
    'Ctrl/Cmd + R': 'Refresh',
    'Ctrl/Cmd + P': 'Print/Export',
    'Esc': 'Close dialog/Go back',
    '/': 'Focus search',
  };

  /// Check if the shortcut matches the given key event
  static bool isNewItem(KeyEvent event) {
    return event is KeyDownEvent &&
        (event.logicalKey == LogicalKeyboardKey.keyN) &&
        (HardwareKeyboard.instance.isControlPressed ||
            HardwareKeyboard.instance.isMetaPressed);
  }

  static bool isSave(KeyEvent event) {
    return event is KeyDownEvent &&
        (event.logicalKey == LogicalKeyboardKey.keyS) &&
        (HardwareKeyboard.instance.isControlPressed ||
            HardwareKeyboard.instance.isMetaPressed);
  }

  static bool isSearch(KeyEvent event) {
    return event is KeyDownEvent &&
        (event.logicalKey == LogicalKeyboardKey.keyF) &&
        (HardwareKeyboard.instance.isControlPressed ||
            HardwareKeyboard.instance.isMetaPressed);
  }

  static bool isRefresh(KeyEvent event) {
    return event is KeyDownEvent &&
        (event.logicalKey == LogicalKeyboardKey.keyR) &&
        (HardwareKeyboard.instance.isControlPressed ||
            HardwareKeyboard.instance.isMetaPressed);
  }

  static bool isPrint(KeyEvent event) {
    return event is KeyDownEvent &&
        (event.logicalKey == LogicalKeyboardKey.keyP) &&
        (HardwareKeyboard.instance.isControlPressed ||
            HardwareKeyboard.instance.isMetaPressed);
  }

  static bool isEscape(KeyEvent event) {
    return event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape;
  }

  static bool isSlash(KeyEvent event) {
    return event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.slash;
  }

  /// Widget to display available keyboard shortcuts
  static Widget buildShortcutsHelpDialog(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(
            Icons.keyboard,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 8),
          const Text('Keyboard Shortcuts'),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: shortcuts.entries.map((entry) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.grey[400]!),
                    ),
                    child: Text(
                      entry.key,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      entry.value,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }

  /// Show keyboard shortcuts help dialog
  static void showShortcutsHelp(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => buildShortcutsHelpDialog(context),
    );
  }
}
