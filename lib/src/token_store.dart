import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persistent storage for the visitor token.
///
/// The default, [SecureLetsBotTokenStore], keeps it in the iOS Keychain or
/// Android Keystore-backed storage. Implement this to plug in your own
/// secure store; never use plain shared preferences or files.
abstract class LetsBotTokenStore {
  /// Returns the stored value for [key], or `null`.
  Future<String?> read(String key);

  /// Stores [value] under [key].
  Future<void> write(String key, String value);

  /// Removes [key].
  Future<void> delete(String key);
}

/// [LetsBotTokenStore] backed by `flutter_secure_storage`.
class SecureLetsBotTokenStore implements LetsBotTokenStore {
  /// Creates the store. Keychain items are readable after first unlock (so
  /// background push handling works) and never leave this device.
  const SecureLetsBotTokenStore()
      : _storage = const FlutterSecureStorage(
          iOptions: IOSOptions(
            accessibility: KeychainAccessibility.first_unlock_this_device,
          ),
        );

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) async {
    try {
      return await _storage.read(key: key);
    } on PlatformException {
      // Unreadable (e.g. keystore reset after a backup restore): start over.
      await delete(key);
      return null;
    }
  }

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) async {
    try {
      await _storage.delete(key: key);
    } on PlatformException {
      // Nothing more we can do; the next write overwrites it.
    }
  }
}

/// In-memory [LetsBotTokenStore] for tests and previews. Not persistent.
class MemoryLetsBotTokenStore implements LetsBotTokenStore {
  /// Creates an empty store, optionally pre-filled with [values].
  MemoryLetsBotTokenStore([Map<String, String>? values])
      : values = {...?values};

  /// Current contents.
  final Map<String, String> values;

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}
